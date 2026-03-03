import Foundation
import CoreHaptics

@MainActor
public final class TimelinePreviewPlayer {
    public static var supportsHaptics: Bool {
        HapticPlayer.supportsHaptics
    }

    public private(set) var isPrepared = false

    public var isPlaying: Bool { player.isPlaying }
    public var currentTime: TimeInterval { player.audioCurrentTime }
    public var duration: TimeInterval { analysis?.duration ?? 0 }

    public var lookahead: TimeInterval = 2.0
    public var lookbehind: TimeInterval = 0.5

    private let compiler = TimelineCompiler()
    private let exporter = HapticExporter()
    private let player = HapticPlayer()

    private var audioURL: URL?
    private var analysis: MultiChannelAnalysisResult?
    private var document: HapticTimelineDocument?
    private var settings: GeneratorSettings = .init()

    private var preparedRange: ClosedRange<TimeInterval> = 0...0

    public init() {}

    public func prepare(
        audioURL: URL,
        analysis: MultiChannelAnalysisResult,
        document: HapticTimelineDocument,
        settings: GeneratorSettings = .init()
    ) throws {
        self.audioURL = audioURL
        self.analysis = analysis
        self.document = document
        self.settings = settings

        try rebuildWindow(at: 0)
        isPrepared = true
    }

    public func play() throws {
        guard isPrepared else {
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailPrepareFirst)
        }

        if !player.isPlaying {
            try player.play()
            let offset = max(0, player.audioCurrentTime - preparedRange.lowerBound)
            try player.seek(audioTime: player.audioCurrentTime, hapticOffset: offset)
        }
    }

    public func pause() {
        player.pause()
    }

    public func stop() {
        player.stop()
    }

    public func seek(to time: TimeInterval) throws {
        guard isPrepared else {
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailPrepareFirst)
        }

        let wasPlaying = player.isPlaying
        try rebuildWindow(at: time)

        if wasPlaying {
            try player.play()
            let offset = max(0, time - preparedRange.lowerBound)
            try player.seek(audioTime: time, hapticOffset: offset)
        } else {
            try player.seek(audioTime: time, hapticOffset: max(0, time - preparedRange.lowerBound))
        }
    }

    public func updateDocument(_ document: HapticTimelineDocument) throws {
        guard isPrepared else {
            self.document = document
            return
        }

        self.document = document
        let current = player.audioCurrentTime
        let wasPlaying = player.isPlaying

        try rebuildWindow(at: current)
        if wasPlaying {
            try player.play()
            try player.seek(audioTime: current, hapticOffset: max(0, current - preparedRange.lowerBound))
        }
    }

    private func rebuildWindow(at time: TimeInterval) throws {
        guard let audioURL, let analysis, let document else {
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailPrepareFirst)
        }

        let lower = max(0, time - lookbehind)
        let upper = min(analysis.duration, time + lookahead)
        let range = lower...max(lower + 0.05, upper)

        let descriptor = try compiler.compileWindow(
            document: document,
            analysis: analysis,
            settings: settings,
            timeRange: range
        )

        let pattern = try exporter.makePattern(descriptor)
        try player.prepare(audioURL: audioURL, pattern: pattern)

        preparedRange = range
    }
}
