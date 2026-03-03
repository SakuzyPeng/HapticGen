import Foundation
import AVFoundation
import CoreHaptics
import SwiftUI

@MainActor
final class TimelineEditorViewModel: ObservableObject {
    enum InspectorTab: String, CaseIterable, Identifiable {
        case source = "Source"
        case haptic = "Haptic"
        case curve = "Curve"
        case transient = "Transient"
        case channelMap = "Channel Map"

        var id: String { rawValue }
    }

    @Published var selectedAudioURL: URL?
    @Published var fileName: String = "-"
    @Published var durationText: String = "-"
    @Published var channelCount: Int = 0

    @Published var analysisResult: MultiChannelAnalysisResult?
    @Published var timelineDocument: HapticTimelineDocument?

    @Published var selectedTrackID: UUID?
    @Published var selectedClipID: UUID?
    @Published var inspectorTab: InspectorTab = .source

    @Published var zoomScale: CGFloat = 90
    @Published var playhead: TimeInterval = 0
    @Published var selectedTemplate: TimelineTemplate = .trailer

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var isPlaying = false
    @Published var statusMessage = "Import an audio file to start"
    @Published var errorMessage: String?
    @Published var exportedAHAPPath = "-"

    private let analyzer = AudioAnalyzer()
    private let compiler = TimelineCompiler()
    private let exporter = HapticExporter()
    private let previewPlayer = TimelinePreviewPlayer()
    private let strategyResolver = DefaultHapticStrategyResolver()
    private let minKeyframeSpacing: TimeInterval = 0.01
    private let maxKeyframesPerCurve: Int = 256

    private var debouncePreviewTask: Task<Void, Never>?
    private var playheadTask: Task<Void, Never>?

    var timelineDuration: TimeInterval {
        timelineDocument?.duration ?? analysisResult?.duration ?? 1
    }

    var timelineWidth: CGFloat {
        CGFloat(timelineDuration) * zoomScale
    }

    var selectedTrack: HapticTrack? {
        guard let trackID = selectedTrackID else { return nil }
        return timelineDocument?.tracks.first(where: { $0.id == trackID })
    }

    var selectedClip: TimelineClip? {
        guard let track = selectedTrack, let clipID = selectedClipID else { return nil }
        return track.clips.first(where: { $0.id == clipID })
    }

    deinit {
        debouncePreviewTask?.cancel()
        playheadTask?.cancel()
    }

    func importAudio(url: URL) {
        do {
            let localURL = try makeLocalCopyIfNeeded(from: url)
            selectedAudioURL = localURL
            fileName = localURL.lastPathComponent

            let file = try AVAudioFile(forReading: localURL)
            channelCount = Int(file.processingFormat.channelCount)
            durationText = Self.formatDuration(Double(file.length) / file.processingFormat.sampleRate)

            analysisResult = nil
            timelineDocument = nil
            selectedTrackID = nil
            selectedClipID = nil
            playhead = 0
            exportedAHAPPath = "-"
            isPlaying = false
            statusMessage = "Audio imported. Run Analyze."
        } catch {
            showError(AudioHapticError.invalidAudioFormat)
        }
    }

    func analyzeAudio() {
        guard let selectedAudioURL else {
            showError(AudioHapticError.invalidAnalysis(L10n.Key.errorDetailImportAudioFirst))
            return
        }

        isAnalyzing = true
        analysisProgress = 0
        statusMessage = "Analyzing..."

        Task {
            do {
                let result = try await analyzer.analyze(url: selectedAudioURL) { [weak self] progress in
                    Task { @MainActor in
                        self?.analysisProgress = progress
                    }
                }

                analysisResult = result
                let strategy = strategyResolver.resolve(analysis: result, layout: result.layout, profile: .musicTrailer)
                let doc = HapticTimelineDocument.default(for: result, template: selectedTemplate, strategy: strategy)
                timelineDocument = doc
                selectedTrackID = doc.tracks.first?.id
                selectedClipID = doc.tracks.first?.clips.first?.id
                statusMessage = "Timeline ready. Start editing clips and keyframes."
                try prepareRealtimePreviewIfPossible()
            } catch {
                showError(error)
            }

            isAnalyzing = false
        }
    }

    func applyTemplate(_ template: TimelineTemplate) {
        selectedTemplate = template
        guard let analysis = analysisResult else { return }

        let strategy = strategyResolver.resolve(analysis: analysis, layout: analysis.layout, profile: .musicTrailer)
        let doc = HapticTimelineDocument.default(for: analysis, template: template, strategy: strategy)
        timelineDocument = doc
        selectedTrackID = doc.tracks.first?.id
        selectedClipID = doc.tracks.first?.clips.first?.id
        statusMessage = "Template applied: \(template.rawValue)"
        schedulePreviewRefresh()
    }

    func addTrack() {
        guard var doc = timelineDocument else { return }
        guard doc.tracks.count < HapticTimelineDocument.maxTracks else {
            statusMessage = "Track limit reached (\(HapticTimelineDocument.maxTracks))."
            return
        }

        let newTrack = HapticTrack(
            name: "Track \(doc.tracks.count + 1)",
            style: .continuous,
            source: TrackSource(channelGroup: .all, frequencyBand: .mid),
            mixWeight: 0.8,
            maxOutput: 0.8,
            clips: [TimelineClip(start: playhead, duration: min(4, max(1, doc.duration - playhead)))]
        )

        doc.tracks.append(newTrack)
        timelineDocument = doc
        selectedTrackID = newTrack.id
        selectedClipID = newTrack.clips.first?.id
        schedulePreviewRefresh()
    }

    func addClip(to trackID: UUID) {
        guard var doc = timelineDocument,
              let index = doc.tracks.firstIndex(where: { $0.id == trackID })
        else { return }

        let remaining = max(1, doc.duration - playhead)
        let clip = TimelineClip(start: playhead, duration: min(4, remaining))
        doc.tracks[index].clips.append(clip)
        doc.tracks[index].clips.sort { $0.start < $1.start }

        timelineDocument = doc
        selectedTrackID = trackID
        selectedClipID = clip.id
        schedulePreviewRefresh()
    }

    func removeSelectedClip() {
        guard var doc = timelineDocument,
              let trackID = selectedTrackID,
              let clipID = selectedClipID,
              let trackIndex = doc.tracks.firstIndex(where: { $0.id == trackID })
        else { return }

        doc.tracks[trackIndex].clips.removeAll { $0.id == clipID }
        timelineDocument = doc
        selectedClipID = doc.tracks[trackIndex].clips.first?.id
        schedulePreviewRefresh()
    }

    func select(trackID: UUID, clipID: UUID?) {
        selectedTrackID = trackID
        selectedClipID = clipID
    }

    func setTrackMuted(_ isMuted: Bool, trackID: UUID) {
        mutateTrack(trackID) { track in
            track.isMuted = isMuted
        }
    }

    func setTrackSolo(_ isSolo: Bool, trackID: UUID) {
        mutateTrack(trackID) { track in
            track.isSolo = isSolo
        }
    }

    func setTrackEnabled(_ enabled: Bool, trackID: UUID) {
        mutateTrack(trackID) { track in
            track.isEnabled = enabled
        }
    }

    func setTrackStyle(_ style: TrackHapticStyle) {
        guard let trackID = selectedTrackID else { return }
        mutateTrack(trackID) { track in
            track.style = style
        }
    }

    func setTrackMixWeight(_ value: Float) {
        guard let trackID = selectedTrackID else { return }
        mutateTrack(trackID) { track in
            track.mixWeight = max(0, value)
        }
    }

    func setTrackMaxOutput(_ value: Float) {
        guard let trackID = selectedTrackID else { return }
        mutateTrack(trackID) { track in
            track.maxOutput = max(0, min(1, value))
        }
    }

    func setTrackChannelGroupKind(_ kind: ChannelGroupKind) {
        guard let trackID = selectedTrackID else { return }
        mutateTrack(trackID) { track in
            track.source.channelGroup.kind = kind
        }
    }

    func setTrackFrequencyBandKind(_ kind: FrequencyBandKind) {
        guard let trackID = selectedTrackID else { return }
        mutateTrack(trackID) { track in
            track.source.frequencyBand.kind = kind
        }
    }

    func setCustomChannelLabels(_ text: String) {
        guard let trackID = selectedTrackID else { return }
        let labels = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        mutateTrack(trackID) { track in
            track.source.channelGroup.customLabels = labels
            track.source.channelGroup.kind = .custom
        }
    }

    func setCustomFrequency(minHz: Float, maxHz: Float) {
        guard let trackID = selectedTrackID else { return }
        mutateTrack(trackID) { track in
            track.source.frequencyBand.kind = .custom
            track.source.frequencyBand.customMinHz = minHz
            track.source.frequencyBand.customMaxHz = maxHz
        }
    }

    func setSelectedClipStart(_ value: TimeInterval) {
        mutateSelectedClip { clip in
            clip.start = max(0, min(value, timelineDuration - 0.05))
        }
    }

    func setSelectedClipDuration(_ value: TimeInterval) {
        mutateSelectedClip { clip in
            clip.duration = max(0.05, min(value, timelineDuration - clip.start))
        }
    }

    func setTransientThreshold(_ value: Float) {
        mutateSelectedClip { clip in
            clip.transientRule.threshold = max(0, min(1, value))
        }
    }

    func setTransientCooldown(_ value: TimeInterval) {
        mutateSelectedClip { clip in
            clip.transientRule.cooldown = max(0, value)
        }
    }

    func setTransientGain(_ value: Float) {
        mutateSelectedClip { clip in
            clip.transientRule.gain = max(0, value)
        }
    }

    func setPulseRate(_ value: Float) {
        mutateSelectedClip { clip in
            clip.pulseRate = max(0.5, min(20, value))
        }
    }

    func setPulseDepth(_ value: Float) {
        mutateSelectedClip { clip in
            clip.pulseDepth = max(0, min(1, value))
        }
    }

    func addIntensityKeyframeAtPlayhead(value: Float) {
        addKeyframe(at: playhead, value: value, type: .intensity)
    }

    func addSharpnessKeyframeAtPlayhead(value: Float) {
        addKeyframe(at: playhead, value: value, type: .sharpness)
    }

    func addIntensityKeyframe(trackID: UUID, clipID: UUID, normalizedTime: TimeInterval) {
        mutateClip(trackID: trackID, clipID: clipID) { clip in
            let normalized = max(0, min(1, normalizedTime))
            let absolute = clip.start + clip.duration * normalized
            let value = self.evaluate(keyframes: clip.intensityKeyframes, atNormalizedTime: normalized)
            self.playhead = absolute
            self.insertKeyframe(
                TrackKeyframe(time: normalized, value: value),
                into: &clip.intensityKeyframes
            )
        }
    }

    func removeNearestIntensityKeyframe() {
        removeNearestKeyframe(type: .intensity)
    }

    func removeNearestSharpnessKeyframe() {
        removeNearestKeyframe(type: .sharpness)
    }

    func togglePlayback() {
        if isPlaying {
            previewPlayer.pause()
            isPlaying = false
            playheadTask?.cancel()
            statusMessage = "Paused"
            return
        }

        do {
            try prepareRealtimePreviewIfPossible()
            try previewPlayer.seek(to: playhead)
            try previewPlayer.play()
            isPlaying = true
            statusMessage = "Playing timeline preview"
            startPlayheadSync()
        } catch {
            showError(error)
        }
    }

    func stopPlayback() {
        previewPlayer.stop()
        isPlaying = false
        playheadTask?.cancel()
        playhead = 0
    }

    func seek(to time: TimeInterval) {
        let bounded = max(0, min(time, timelineDuration))
        playhead = bounded
        do {
            try prepareRealtimePreviewIfPossible()
            try previewPlayer.seek(to: bounded)
        } catch {
            showError(error)
        }
    }

    func exportAHAP() {
        guard let analysis = analysisResult, let document = timelineDocument else {
            showError(AudioHapticError.exportFailed(L10n.Key.errorDetailCompleteAnalysisFirst))
            return
        }
        guard let selectedAudioURL else {
            showError(AudioHapticError.exportFailed(L10n.Key.errorDetailSourceAudioMissing))
            return
        }

        do {
            let descriptor = try compiler.compile(document: document, analysis: analysis, settings: .init())
            let outputName = selectedAudioURL.deletingPathExtension().lastPathComponent + "_timeline.ahap"
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputName)
            try exporter.exportAHAP(descriptor, to: outputURL)
            exportedAHAPPath = outputURL.path
            statusMessage = "Exported: \(outputURL.lastPathComponent)"
        } catch {
            showError(error)
        }
    }

    func updateZoom(_ factor: CGFloat) {
        zoomScale = min(240, max(40, zoomScale * factor))
    }

    private func prepareRealtimePreviewIfPossible() throws {
        guard let selectedAudioURL, let analysis = analysisResult, let document = timelineDocument else {
            throw AudioHapticError.playbackFailed(L10n.Key.errorDetailCompleteAnalysisFirst)
        }

        if !TimelinePreviewPlayer.supportsHaptics {
            throw AudioHapticError.unsupportedHaptics
        }

        try previewPlayer.prepare(audioURL: selectedAudioURL, analysis: analysis, document: document)
    }

    private func schedulePreviewRefresh() {
        debouncePreviewTask?.cancel()
        debouncePreviewTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                do {
                    guard self.previewPlayer.isPrepared, let document = self.timelineDocument else { return }
                    try self.previewPlayer.updateDocument(document)
                    if self.isPlaying {
                        self.statusMessage = "Preview updated"
                    }
                } catch {
                    self.showError(error)
                }
            }
        }
    }

    private func startPlayheadSync() {
        playheadTask?.cancel()
        playheadTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                await MainActor.run {
                    guard self.isPlaying else { return }
                    self.playhead = self.previewPlayer.currentTime
                    if self.playhead >= self.timelineDuration {
                        self.isPlaying = false
                        self.playheadTask?.cancel()
                    }
                }
            }
        }
    }

    private func mutateTrack(_ trackID: UUID, transform: (inout HapticTrack) -> Void) {
        guard var doc = timelineDocument,
              let index = doc.tracks.firstIndex(where: { $0.id == trackID })
        else { return }

        transform(&doc.tracks[index])
        timelineDocument = doc
        schedulePreviewRefresh()
    }

    private func mutateSelectedClip(_ transform: (inout TimelineClip) -> Void) {
        guard var doc = timelineDocument,
              let trackID = selectedTrackID,
              let clipID = selectedClipID,
              let trackIndex = doc.tracks.firstIndex(where: { $0.id == trackID }),
              let clipIndex = doc.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID })
        else { return }

        transform(&doc.tracks[trackIndex].clips[clipIndex])
        timelineDocument = doc
        schedulePreviewRefresh()
    }

    private func mutateClip(trackID: UUID, clipID: UUID, transform: (inout TimelineClip) -> Void) {
        guard var doc = timelineDocument,
              let trackIndex = doc.tracks.firstIndex(where: { $0.id == trackID }),
              let clipIndex = doc.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID })
        else { return }

        selectedTrackID = trackID
        selectedClipID = clipID
        transform(&doc.tracks[trackIndex].clips[clipIndex])
        timelineDocument = doc
        schedulePreviewRefresh()
    }

    private enum KeyframeType {
        case intensity
        case sharpness
    }

    private func addKeyframe(at absoluteTime: TimeInterval, value: Float, type: KeyframeType) {
        mutateSelectedClip { clip in
            guard clip.duration > 0 else { return }
            let local = max(0, min(1, (absoluteTime - clip.start) / clip.duration))
            let keyframe = TrackKeyframe(time: local, value: value)

            switch type {
            case .intensity:
                insertKeyframe(keyframe, into: &clip.intensityKeyframes)
            case .sharpness:
                insertKeyframe(keyframe, into: &clip.sharpnessKeyframes)
            }
        }
    }

    private func removeNearestKeyframe(type: KeyframeType) {
        mutateSelectedClip { clip in
            guard clip.duration > 0 else { return }
            let local = max(0, min(1, (playhead - clip.start) / clip.duration))

            switch type {
            case .intensity:
                guard clip.intensityKeyframes.count > 2 else { return }
                if let nearest = clip.intensityKeyframes.enumerated().min(by: { abs($0.element.time - local) < abs($1.element.time - local) }) {
                    clip.intensityKeyframes.remove(at: nearest.offset)
                }
            case .sharpness:
                guard clip.sharpnessKeyframes.count > 2 else { return }
                if let nearest = clip.sharpnessKeyframes.enumerated().min(by: { abs($0.element.time - local) < abs($1.element.time - local) }) {
                    clip.sharpnessKeyframes.remove(at: nearest.offset)
                }
            }
        }
    }

    private func insertKeyframe(_ keyframe: TrackKeyframe, into keyframes: inout [TrackKeyframe]) {
        if keyframes.count >= maxKeyframesPerCurve {
            statusMessage = "Keyframe limit reached (\(maxKeyframesPerCurve))."
            return
        }

        if let nearest = keyframes.enumerated().min(by: { abs($0.element.time - keyframe.time) < abs($1.element.time - keyframe.time) }),
           abs(nearest.element.time - keyframe.time) < minKeyframeSpacing {
            keyframes[nearest.offset] = TrackKeyframe(id: nearest.element.id, time: keyframe.time, value: keyframe.value)
            keyframes.sort { $0.time < $1.time }
            return
        }

        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }

    private func evaluate(keyframes: [TrackKeyframe], atNormalizedTime normalizedTime: TimeInterval) -> Float {
        let t = Float(max(0, min(1, normalizedTime)))
        guard !keyframes.isEmpty else { return 0.5 }
        let sorted = keyframes.sorted { $0.time < $1.time }

        if t <= Float(sorted[0].time) {
            return sorted[0].value
        }
        if let last = sorted.last, t >= Float(last.time) {
            return last.value
        }

        for index in 0..<(sorted.count - 1) {
            let lhs = sorted[index]
            let rhs = sorted[index + 1]
            let lhsT = Float(lhs.time)
            let rhsT = Float(rhs.time)
            guard t >= lhsT && t <= rhsT else { continue }

            let span = max(0.0001, rhsT - lhsT)
            let progress = (t - lhsT) / span
            return lhs.value + (rhs.value - lhs.value) * progress
        }

        return sorted.last?.value ?? 0.5
    }

    private func showError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = "Error"
        isPlaying = false
        isAnalyzing = false
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let minute = Int(seconds) / 60
        let second = Int(seconds) % 60
        return String(format: "%d:%02d", minute, second)
    }

    private func makeLocalCopyIfNeeded(from sourceURL: URL) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioHapticImports", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let destination = temporaryDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
