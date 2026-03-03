import Foundation
import AVFoundation
import CoreHaptics
import ZIPFoundation

/// 从 Haptic Trailer zip 包或 .m3u8 清单加载，同步驱动音频与 Taptic Engine
///
/// 支持两种输入：
/// - `.zip`：自动解压到临时目录，再解析内部的 manifest.m3u8
/// - `.m3u8`：直接解析，路径按相对路径（相对于清单目录）或绝对 file:// 解析
@MainActor
public final class HapticTrailerPlayer {
    public private(set) var isPlaying = false
    /// 解压/解析后的音频文件 URL，分享时可附上
    public private(set) var loadedAudioURL: URL?

    private var engine: CHHapticEngine?
    private var advancedPlayer: CHHapticAdvancedPatternPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var loadedPattern: CHHapticPattern?
    private var unzipDir: URL?

    public init() {}

    // MARK: - Public API

    public func load(manifestURL: URL) throws {
        let actualManifestURL: URL

        if manifestURL.pathExtension.lowercased() == "zip" {
            actualManifestURL = try unzipAndFindManifest(zipURL: manifestURL)
        } else {
            actualManifestURL = manifestURL
        }

        let content = try String(contentsOf: actualManifestURL, encoding: .utf8)
        let baseURL  = actualManifestURL.deletingLastPathComponent()
        let (ahapURL, audioURL) = try parseManifest(content, baseURL: baseURL)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let pattern = try CHHapticPattern(contentsOf: ahapURL)
        let audio   = try AVAudioPlayer(contentsOf: audioURL)
        audio.prepareToPlay()

        self.loadedPattern   = pattern
        self.loadedAudioURL  = audioURL
        self.audioPlayer     = audio

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
            try advancedPlayer?.seek(toOffset: bounded)
        }
    }

    public func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        try? advancedPlayer?.stop(atTime: CHHapticTimeImmediate)
        isPlaying = false
    }

    public var audioCurrentTime: TimeInterval { audioPlayer?.currentTime ?? 0 }
    public var audioDuration: TimeInterval     { audioPlayer?.duration ?? 0 }

    // MARK: - zip 解压

    private func unzipAndFindManifest(zipURL: URL) throws -> URL {
        let fm = FileManager.default
        let destDir = fm.temporaryDirectory
            .appendingPathComponent("haptic_unzip_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try fm.unzipItem(at: zipURL, to: destDir)
        self.unzipDir = destDir

        let contents = try fm.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil)
        guard let found = contents.first(where: { $0.pathExtension.lowercased() == "m3u8" }) else {
            throw AudioHapticError.invalidAnalysis("zip 包中未找到 .m3u8 清单")
        }
        return found
    }

    // MARK: - Manifest Parsing

    private func parseManifest(_ content: String, baseURL: URL) throws -> (ahapURL: URL, audioURL: URL) {
        var ahapURL:  URL?
        var audioURL: URL?
        var nextIsAudio = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains(#"DATA-ID="com.apple.hls.haptics.url""#) {
                ahapURL = extractValue(from: trimmed).flatMap { resolve($0, baseURL: baseURL) }
            } else if trimmed.hasPrefix("#EXTINF:") {
                nextIsAudio = true
            } else if nextIsAudio && !trimmed.hasPrefix("#") {
                audioURL = resolve(trimmed, baseURL: baseURL)
                nextIsAudio = false
            }
        }

        guard let ahap  = ahapURL  else { throw AudioHapticError.invalidAnalysis("清单缺少 AHAP URL") }
        guard let audio = audioURL else { throw AudioHapticError.invalidAnalysis("清单缺少音频 URL") }
        return (ahap, audio)
    }

    /// 相对路径 → 相对于 baseURL；绝对 URL → 直接使用
    private func resolve(_ value: String, baseURL: URL) -> URL? {
        if value.hasPrefix("file://") || value.hasPrefix("http://") || value.hasPrefix("https://") {
            return URL(string: value)
        }
        return baseURL.appendingPathComponent(value)
    }

    private func extractValue(from line: String) -> String? {
        guard let start = line.range(of: #"VALUE=""#),
              let end   = line.range(of: "\"", range: start.upperBound..<line.endIndex) else {
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
            Task { @MainActor in self?.isPlaying = false }
        }
        try newEngine.start()
        self.engine = newEngine
        return newEngine
    }
}
