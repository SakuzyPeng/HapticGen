import Foundation
import AVFoundation
import CoreHaptics

/// 从本地 HLS 清单（.m3u8）解析触觉旁路轨，同步驱动音频与 Taptic Engine
///
/// 解析逻辑：
/// - `#EXT-X-SESSION-DATA:DATA-ID="com.apple.hls.haptics.url",VALUE="..."` → ahapURL
/// - `#EXTINF:` 下一行非注释行 → audioURL
@MainActor
public final class HapticTrailerPlayer {
    public private(set) var isPlaying = false
    /// 从清单解析出的音频文件 URL，分享时需一并附上
    public private(set) var loadedAudioURL: URL?

    private var engine: CHHapticEngine?
    private var advancedPlayer: CHHapticAdvancedPatternPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var loadedPattern: CHHapticPattern?

    public init() {}

    // MARK: - Public API

    public func load(manifestURL: URL) throws {
        let content = try String(contentsOf: manifestURL, encoding: .utf8)
        let (ahapURL, audioURL) = try parseManifest(content)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let pattern = try CHHapticPattern(contentsOf: ahapURL)
        let audio = try AVAudioPlayer(contentsOf: audioURL)
        audio.prepareToPlay()

        self.loadedPattern = pattern
        self.loadedAudioURL = audioURL
        self.audioPlayer = audio

        let engine = try makeOrReuseEngine()
        self.advancedPlayer = try engine.makeAdvancedPlayer(with: pattern)
    }

    public func play() throws {
        guard let audioPlayer, let loadedPattern else {
            throw AudioHapticError.playbackFailed("请先 load 清单")
        }

        let engine = try makeOrReuseEngine()
        if advancedPlayer == nil {
            advancedPlayer = try engine.makeAdvancedPlayer(with: loadedPattern)
        }

        try engine.start()
        try advancedPlayer?.start(atTime: CHHapticTimeImmediate)
        audioPlayer.play()
        isPlaying = true
    }

    public func pause() {
        audioPlayer?.pause()
        try? advancedPlayer?.stop(atTime: CHHapticTimeImmediate)
        isPlaying = false
    }

    public func seek(to time: TimeInterval) throws {
        guard let audioPlayer else {
            throw AudioHapticError.playbackFailed("请先 load 清单")
        }
        let bounded = max(0, min(time, audioPlayer.duration))
        audioPlayer.currentTime = bounded
        if isPlaying {
            try advancedPlayer?.stop(atTime: CHHapticTimeImmediate)
            try play()
        }
    }

    public func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        try? advancedPlayer?.stop(atTime: CHHapticTimeImmediate)
        isPlaying = false
    }

    public var audioCurrentTime: TimeInterval {
        audioPlayer?.currentTime ?? 0
    }

    public var audioDuration: TimeInterval {
        audioPlayer?.duration ?? 0
    }

    // MARK: - Manifest Parsing

    private func parseManifest(_ content: String) throws -> (ahapURL: URL, audioURL: URL) {
        var ahapURL: URL?
        var audioURL: URL?
        var nextIsAudio = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains(#"DATA-ID="com.apple.hls.haptics.url""#) {
                ahapURL = extractValue(from: trimmed).flatMap { URL(string: $0) }
            } else if trimmed.hasPrefix("#EXTINF:") {
                nextIsAudio = true
            } else if nextIsAudio && !trimmed.hasPrefix("#") {
                audioURL = URL(string: trimmed)
                nextIsAudio = false
            }
        }

        guard let ahap = ahapURL else {
            throw AudioHapticError.invalidAnalysis("清单缺少 AHAP URL (com.apple.hls.haptics.url)")
        }
        guard let audio = audioURL else {
            throw AudioHapticError.invalidAnalysis("清单缺少音频 URL (#EXTINF)")
        }

        return (ahap, audio)
    }

    /// 从 `KEY="VALUE"` 格式中提取 VALUE
    private func extractValue(from line: String) -> String? {
        guard let start = line.range(of: #"VALUE=""#),
              let end = line.range(of: "\"", range: start.upperBound..<line.endIndex) else {
            return nil
        }
        return String(line[start.upperBound..<end.lowerBound])
    }

    // MARK: - Engine Management

    private func makeOrReuseEngine() throws -> CHHapticEngine {
        if let engine { return engine }

        let newEngine = try CHHapticEngine()
        newEngine.resetHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try self.engine?.start()
                    if let pattern = self.loadedPattern {
                        self.advancedPlayer = try self.engine?.makeAdvancedPlayer(with: pattern)
                    }
                } catch {
                    self.isPlaying = false
                }
            }
        }
        newEngine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
        try newEngine.start()
        self.engine = newEngine
        return newEngine
    }
}
