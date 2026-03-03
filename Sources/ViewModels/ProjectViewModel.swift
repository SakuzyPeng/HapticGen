import Foundation
import AVFoundation
import CoreHaptics

@MainActor
final class ProjectViewModel: ObservableObject {
    @Published var selectedAudioURL: URL?
    @Published var fileName: String = "-"
    @Published var channelCount: Int = 0
    @Published var durationText: String = "-"

    @Published var settings: GeneratorSettings = .init()
    @Published var mapping: ChannelMapping = .init(intensity: [], sharpness: [], transient: [])

    @Published var analysisResult: MultiChannelAnalysisResult?
    @Published var patternDescriptor: HapticPatternDescriptor?
    @Published var generatedPattern: CHHapticPattern?

    @Published var analysisProgress: Double = 0
    @Published var isAnalyzing: Bool = false
    @Published var isGenerating: Bool = false
    @Published var isPlaying: Bool = false

    @Published var statusMessage: String = "请选择音频文件"
    @Published var errorMessage: String?
    @Published var exportedAHAPPath: String = "-"

    @Published var trailerZipURL: URL?
    @Published var showTrailerPlayer: Bool = false

    private let analyzer = AudioAnalyzer()
    private let generator = HapticGenerator()
    private let exporter = HapticExporter()
    private let player = HapticPlayer()

    private var regenerateTask: Task<Void, Never>?

    deinit {
        regenerateTask?.cancel()
    }

    func importAudio(url: URL) {
        do {
            let localURL = try makeLocalCopyIfNeeded(from: url)
            selectedAudioURL = localURL
            fileName = localURL.lastPathComponent

            let file = try AVAudioFile(forReading: localURL)
            channelCount = Int(file.processingFormat.channelCount)
            durationText = Self.formatDuration(Double(file.length) / file.processingFormat.sampleRate)
            statusMessage = "已导入音频，点击 Analyze 开始分析"

            analysisResult = nil
            patternDescriptor = nil
            generatedPattern = nil
            mapping = .init(intensity: [], sharpness: [], transient: [])
            exportedAHAPPath = "-"
        } catch {
            showError(AudioHapticError.invalidAudioFormat)
        }
    }

    func analyzeAudio() {
        guard let selectedAudioURL else {
            showError(AudioHapticError.invalidAnalysis("请先导入音频"))
            return
        }

        isAnalyzing = true
        analysisProgress = 0
        statusMessage = "分析中..."

        Task {
            do {
                let result = try await analyzer.analyze(url: selectedAudioURL) { [weak self] progress in
                    Task { @MainActor in
                        self?.analysisProgress = progress
                    }
                }

                analysisResult = result
                mapping = ChannelMapping.defaults(for: result.layout)
                statusMessage = "分析完成：\(result.layout.channelCount)ch，可继续 Generate"
            } catch {
                showError(error)
            }

            isAnalyzing = false
        }
    }

    func generatePattern() {
        guard let analysisResult else {
            showError(AudioHapticError.generationFailed("请先完成分析"))
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let descriptor = try generator.generate(from: analysisResult, mapping: mapping, settings: settings)
            let pattern = try exporter.makePattern(descriptor)

            patternDescriptor = descriptor
            generatedPattern = pattern
            statusMessage = "生成完成：\(descriptor.transientEvents.count) 个瞬态事件"
        } catch {
            showError(error)
        }
    }

    func togglePlayback() {
        guard let selectedAudioURL else {
            showError(AudioHapticError.playbackFailed("请先导入音频"))
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
            statusMessage = "已暂停"
            return
        }

        guard let generatedPattern else {
            showError(AudioHapticError.playbackFailed("请先生成触觉 pattern"))
            return
        }

        do {
            try player.prepare(audioURL: selectedAudioURL, pattern: generatedPattern)
            try player.play()
            isPlaying = true
            statusMessage = "播放中"
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

    func packageHapticTrailer() async {
        guard let descriptor = patternDescriptor else {
            showError(AudioHapticError.exportFailed("请先生成 pattern"))
            return
        }
        guard let audioURL = selectedAudioURL else {
            showError(AudioHapticError.exportFailed("缺少源音频文件"))
            return
        }

        let baseName = audioURL.deletingPathExtension().lastPathComponent
        let ahapURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName + "_haptic_trailer")
            .appendingPathExtension("ahap")

        do {
            try exporter.exportAHAP(descriptor, to: ahapURL)
            let zipURL = try HLSPackager().package(audioURL: audioURL, ahapURL: ahapURL)
            trailerZipURL = zipURL
            showTrailerPlayer = true
            statusMessage = "Haptic Trailer 已生成：\(zipURL.lastPathComponent)"
        } catch {
            showError(error)
        }
    }

    func exportAHAP() {
        guard let descriptor = patternDescriptor else {
            showError(AudioHapticError.exportFailed("请先生成 pattern"))
            return
        }

        guard let selectedAudioURL else {
            showError(AudioHapticError.exportFailed("缺少源音频文件"))
            return
        }

        let outputName = selectedAudioURL.deletingPathExtension().lastPathComponent + ".ahap"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputName)

        do {
            try exporter.exportAHAP(descriptor, to: outputURL)
            exportedAHAPPath = outputURL.path
            statusMessage = "导出成功：\(outputURL.lastPathComponent)"
        } catch {
            showError(error)
        }
    }

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

    private func sendLiveParametersIfPossible() {
        guard isPlaying else {
            return
        }

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
        guard analysisResult != nil else {
            return
        }

        regenerateTask?.cancel()
        regenerateTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.generatePattern()
            }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = "发生错误"
        isAnalyzing = false
        isGenerating = false
        isPlaying = false
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
