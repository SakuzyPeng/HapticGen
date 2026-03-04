import Foundation
import AVFoundation
import CoreHaptics

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var selectedAudioURL: URL?
    @Published var fileName: String = L10n.commonPlaceholderDash
    @Published var channelCount: Int = 0
    @Published var durationText: String = L10n.commonPlaceholderDash

    @Published var settings: GeneratorSettings = .init()
    @Published var mapping: ChannelMapping = .init(intensity: [], sharpness: [], transient: [])

    @Published var analysisResult: MultiChannelAnalysisResult?
    @Published var patternDescriptor: HapticPatternDescriptor?
    @Published var generatedPattern: CHHapticPattern?

    // MARK: - Stem Separation State
    @Published var isSeparating: Bool = false
    @Published var separationProgress: Double = 0
    @Published var selectedStem: StemKind = .default
    @Published var separationArtifacts: StemSeparationArtifacts?

    @Published var analysisProgress: Double = 0
    @Published var isAnalyzing: Bool = false
    @Published var isGenerating: Bool = false
    @Published var isPlaying: Bool = false

    @Published var statusMessage: String = L10n.statusSelectAudio
    @Published var errorMessage: String?
    @Published var exportedAHAPPath: String = L10n.commonPlaceholderDash

    @Published var trailerZipURL: URL?
    @Published var showTrailerPlayer: Bool = false
    @Published var showEditor: Bool = false

    private let analyzer: AudioAnalyzer
    private let stemSeparator: StemSeparating
    private let generator = HapticGenerator()
    private let exporter = HapticExporter()
    private let player = HapticPlayer()

    private var regenerateTask: Task<Void, Never>?

    init(
        analyzer: AudioAnalyzer = AudioAnalyzer(),
        stemSeparator: StemSeparating = Spleeter5StemSeparator()
    ) {
        self.analyzer = analyzer
        self.stemSeparator = stemSeparator
    }

    deinit {
        regenerateTask?.cancel()
    }

    // MARK: - Import

    func importAudio(url: URL) {
        do {
            // 清理上一次的分离工作目录
            if let prev = separationArtifacts?.workspaceDirectoryURL {
                try? FileManager.default.removeItem(at: prev)
            }

            let localURL = try makeLocalCopyIfNeeded(from: url)
            selectedAudioURL = localURL
            fileName = localURL.lastPathComponent

            let file = try AVAudioFile(forReading: localURL)
            channelCount = Int(file.processingFormat.channelCount)
            durationText = Self.formatDuration(Double(file.length) / file.processingFormat.sampleRate)
            statusMessage = L10n.statusImportReady

            analysisResult = nil
            patternDescriptor = nil
            generatedPattern = nil
            separationArtifacts = nil
            isSeparating = false
            separationProgress = 0
            mapping = .init(intensity: [], sharpness: [], transient: [])
            exportedAHAPPath = L10n.commonPlaceholderDash
        } catch {
            showError(AudioHapticError.invalidAudioFormat)
        }
    }

    // MARK: - Stem Separation

    func separateStems() {
        guard let selectedAudioURL else { return }

        isSeparating = true
        separationProgress = 0
        separationArtifacts = nil
        analysisResult = nil
        patternDescriptor = nil
        generatedPattern = nil
        statusMessage = L10n.statusSeparating

        Task {
            do {
                let artifacts = try await stemSeparator.separate(
                    inputURL: selectedAudioURL
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.separationProgress = progress
                    }
                }
                separationArtifacts = artifacts
                statusMessage = L10n.statusSeparationCompleted
            } catch {
                showError(error)
            }
            isSeparating = false
        }
    }

    func selectStem(_ stem: StemKind) {
        guard stem != selectedStem else { return }
        selectedStem = stem
        analysisResult = nil
        patternDescriptor = nil
        generatedPattern = nil
    }

    // MARK: - Analyze

    func analyzeAudio() {
        guard let artifacts = separationArtifacts else {
            showError(AudioHapticError.invalidAnalysis(L10n.Key.errorDetailSeparateFirst))
            return
        }

        let stemURL = artifacts.url(for: selectedStem)

        isAnalyzing = true
        analysisProgress = 0
        statusMessage = L10n.statusAnalyzing

        Task {
            do {
                let result = try await analyzer.analyze(url: stemURL) { [weak self] progress in
                    Task { @MainActor in
                        self?.analysisProgress = progress
                    }
                }

                analysisResult = result
                mapping = ChannelMapping.defaults(for: result.layout)
                statusMessage = L10n.statusAnalysisCompleted(channelCount: result.layout.channelCount)
            } catch {
                showError(error)
            }

            isAnalyzing = false
        }
    }

    // MARK: - Generate

    func generatePattern() {
        guard let analysisResult else {
            showError(AudioHapticError.generationFailed(L10n.Key.errorDetailCompleteAnalysisFirst))
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let descriptor = try generator.generate(from: analysisResult, mapping: mapping, settings: settings)
            let pattern = try exporter.makePattern(descriptor)

            patternDescriptor = descriptor
            generatedPattern = pattern
            statusMessage = L10n.statusGenerateCompleted(transientCount: descriptor.transientEvents.count)
            showEditor = true
        } catch {
            showError(error)
        }
    }

    // MARK: - Playback

    func togglePlayback() {
        guard let audioURL = separationArtifacts?.url(for: selectedStem) else {
            showError(AudioHapticError.playbackFailed(L10n.Key.errorDetailSeparateFirst))
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
            statusMessage = L10n.statusPaused
            return
        }

        guard let generatedPattern else {
            showError(AudioHapticError.playbackFailed(L10n.Key.errorDetailGeneratePatternFirst))
            return
        }

        do {
            try player.prepare(audioURL: audioURL, pattern: generatedPattern)
            try player.play()
            isPlaying = true
            statusMessage = L10n.statusPlaying
        } catch {
            showError(error)
        }
    }

    func seek(to time: TimeInterval) {
        do {
            try player.seek(to: time)
        } catch {
            showError(error)
        }
    }

    func stopPlayback() {
        player.stop()
        isPlaying = false
    }

    // MARK: - Export

    func packageHapticTrailer() async {
        guard let descriptor = patternDescriptor else {
            showError(AudioHapticError.exportFailed(L10n.Key.errorDetailGeneratePatternFirst))
            return
        }
        guard let audioURL = separationArtifacts?.url(for: selectedStem) else {
            showError(AudioHapticError.exportFailed(L10n.Key.errorDetailSeparateFirst))
            return
        }

        let baseName = (selectedAudioURL?.deletingPathExtension().lastPathComponent ?? "output")
            + "_\(selectedStem.rawValue)"
        let ahapURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName + "_haptic_trailer")
            .appendingPathExtension("ahap")

        do {
            try exporter.exportAHAP(descriptor, to: ahapURL)
            let zipURL = try HLSPackager().package(audioURL: audioURL, ahapURL: ahapURL)
            trailerZipURL = zipURL
            showTrailerPlayer = true
            statusMessage = L10n.statusTrailerPackaged(fileName: zipURL.lastPathComponent)
        } catch {
            showError(error)
        }
    }

    func exportAHAP() {
        guard let descriptor = patternDescriptor else {
            showError(AudioHapticError.exportFailed(L10n.Key.errorDetailGeneratePatternFirst))
            return
        }

        let outputName = (selectedAudioURL?.deletingPathExtension().lastPathComponent ?? "output")
            + "_\(selectedStem.rawValue).ahap"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputName)

        do {
            try exporter.exportAHAP(descriptor, to: outputURL)
            exportedAHAPPath = outputURL.path
            statusMessage = L10n.statusExportSuccess(fileName: outputURL.lastPathComponent)
        } catch {
            showError(error)
        }
    }

    // MARK: - Settings

    func updateIntensityScale(_ value: Float) {
        settings = GeneratorSettings(
            intensityScale: value,
            sharpnessBias: settings.sharpnessBias,
            eventDensity: settings.eventDensity,
            transientSensitivity: settings.transientSensitivity
        )
        sendLiveParametersIfPossible()
        scheduleDebouncedRegeneration()
    }

    func updateSharpnessBias(_ value: Float) {
        settings = GeneratorSettings(
            intensityScale: settings.intensityScale,
            sharpnessBias: value,
            eventDensity: settings.eventDensity,
            transientSensitivity: settings.transientSensitivity
        )
        sendLiveParametersIfPossible()
        scheduleDebouncedRegeneration()
    }

    func updateEventDensity(_ value: Float) {
        settings = GeneratorSettings(
            intensityScale: settings.intensityScale,
            sharpnessBias: settings.sharpnessBias,
            eventDensity: value,
            transientSensitivity: settings.transientSensitivity
        )
        scheduleDebouncedRegeneration()
    }

    func updateTransientSensitivity(_ value: Float) {
        settings = GeneratorSettings(
            intensityScale: settings.intensityScale,
            sharpnessBias: settings.sharpnessBias,
            eventDensity: settings.eventDensity,
            transientSensitivity: value
        )
        scheduleDebouncedRegeneration()
    }

    // MARK: - Private

    private func sendLiveParametersIfPossible() {
        guard isPlaying else { return }
        do {
            try player.sendLiveParameters(
                intensity: min(1, max(0, settings.intensityScale / 2.0)),
                sharpness: min(1, max(0, settings.sharpnessBias + 0.5))
            )
        } catch {
            showError(error)
        }
    }

    private func scheduleDebouncedRegeneration() {
        guard analysisResult != nil else { return }
        regenerateTask?.cancel()
        regenerateTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.generatePattern() }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = L10n.statusErrorOccurred
        isAnalyzing = false
        isGenerating = false
        isPlaying = false
        isSeparating = false
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
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
