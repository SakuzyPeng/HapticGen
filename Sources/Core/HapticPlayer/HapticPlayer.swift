import Foundation
import AVFoundation
import CoreHaptics

@MainActor
public final class HapticPlayer {
    public static var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private var engine: CHHapticEngine?
    private var advancedPlayer: CHHapticAdvancedPatternPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var pattern: CHHapticPattern?
    private var preparedAudioURL: URL?

    public private(set) var isPlaying = false

    public init() {}

    public func prepare(audioURL: URL, pattern: CHHapticPattern) throws {
        guard Self.supportsHaptics else {
            throw AudioHapticError.unsupportedHaptics
        }

        self.pattern = pattern
        self.preparedAudioURL = audioURL

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let engine = try makeOrReuseEngine()
        self.advancedPlayer = try engine.makeAdvancedPlayer(with: pattern)

        let audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
        audioPlayer.prepareToPlay()
        self.audioPlayer = audioPlayer
    }

    public func play() throws {
        guard let audioPlayer else {
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailPrepareFirst)
        }
        guard let pattern else {
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailPatternMissing)
        }

        let engine = try makeOrReuseEngine()
        if advancedPlayer == nil {
            advancedPlayer = try engine.makeAdvancedPlayer(with: pattern)
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
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailPrepareFirst)
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

    public func sendLiveParameters(intensity: Float?, sharpness: Float?) throws {
        guard let advancedPlayer else {
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailHapticPlayerNotPrepared)
        }

        var dynamicParameters: [CHHapticDynamicParameter] = []

        if let intensity {
            dynamicParameters.append(
                CHHapticDynamicParameter(
                    parameterID: .hapticIntensityControl,
                    value: clamp01(intensity),
                    relativeTime: 0
                )
            )
        }

        if let sharpness {
            dynamicParameters.append(
                CHHapticDynamicParameter(
                    parameterID: .hapticSharpnessControl,
                    value: clamp01(sharpness),
                    relativeTime: 0
                )
            )
        }

        if !dynamicParameters.isEmpty {
            try advancedPlayer.sendParameters(dynamicParameters, atTime: CHHapticTimeImmediate)
        }
    }

    private func makeOrReuseEngine() throws -> CHHapticEngine {
        if let engine {
            return engine
        }

        let newEngine = try CHHapticEngine()
        newEngine.resetHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try self.engine?.start()
                    if let pattern = self.pattern {
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

    private func clamp01(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}
