import Foundation
import CoreHaptics
import AVFoundation

@MainActor
final class TimelineEditorViewModel: ObservableObject {
    // MARK: - 输入（不可变）
    let analysisResult: MultiChannelAnalysisResult
    let audioURL: URL
    let channelLabels: [String]
    let duration: TimeInterval

    // MARK: - 可编辑状态
    @Published var editablePattern: EditableHapticPattern
    @Published var regionMapping: TimeRegionMapping
    @Published var settings: GeneratorSettings

    // MARK: - 视口状态
    @Published var zoom: CGFloat = 1.0  // 0.25 ~ 4.0
    @Published var currentTool: EditorTool = .select

    // MARK: - 选中状态
    @Published var selectedIntensityPointID: UUID?
    @Published var selectedSharpnessPointID: UUID?
    @Published var selectedTransientID: UUID?
    @Published var selectedRegionID: UUID?

    // MARK: - 播放
    @Published var isPlaying: Bool = false
    @Published var playbackTime: TimeInterval = 0

    // MARK: - 内部引擎
    private let generator = HapticGenerator()
    private let exporter = HapticExporter()
    private let player = HapticPlayer()
    private var regenerateTask: Task<Void, Never>?
    private var playbackTimer: Timer?

    // MARK: - 工具枚举
    enum EditorTool: String, CaseIterable {
        case select
        case addTransient
        case addRegion

        var label: String {
            switch self {
            case .select: return L10n.editorToolSelect
            case .addTransient: return L10n.editorToolAddTransient
            case .addRegion: return L10n.editorToolAddRegion
            }
        }

        var systemImage: String {
            switch self {
            case .select: return "cursorarrow"
            case .addTransient: return "waveform.path.badge.plus"
            case .addRegion: return "rectangle.badge.plus"
            }
        }
    }

    // MARK: - 初始化

    init(
        pattern: HapticPatternDescriptor,
        analysisResult: MultiChannelAnalysisResult,
        mapping: ChannelMapping,
        settings: GeneratorSettings,
        audioURL: URL
    ) {
        self.editablePattern = EditableHapticPattern(from: pattern)
        self.analysisResult = analysisResult
        self.regionMapping = TimeRegionMapping(defaultMapping: mapping)
        self.settings = settings
        self.audioURL = audioURL
        self.duration = analysisResult.duration
        self.channelLabels = analysisResult.channels.map(\.label)
    }

    // MARK: - 坐标转换

    func totalContentWidth(viewportWidth: CGFloat) -> CGFloat {
        max(viewportWidth, viewportWidth * zoom)
    }

    func timeToX(_ time: TimeInterval, totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * totalWidth
    }

    func xToTime(_ x: CGFloat, totalWidth: CGFloat) -> TimeInterval {
        guard totalWidth > 0 else { return 0 }
        return max(0, min(duration, Double(x / totalWidth) * duration))
    }

    func playheadX(totalWidth: CGFloat) -> CGFloat {
        timeToX(playbackTime, totalWidth: totalWidth)
    }

    // MARK: - 曲线编辑（直接修改，无需重新生成）

    func moveIntensityPoint(id: UUID, time: TimeInterval, value: Float) {
        guard let idx = editablePattern.intensityCurve.firstIndex(where: { $0.id == id }) else { return }
        editablePattern.intensityCurve[idx].time = max(0, min(duration, time))
        editablePattern.intensityCurve[idx].value = max(0, min(1, value))
    }

    func moveSharpnessPoint(id: UUID, time: TimeInterval, value: Float) {
        guard let idx = editablePattern.sharpnessCurve.firstIndex(where: { $0.id == id }) else { return }
        editablePattern.sharpnessCurve[idx].time = max(0, min(duration, time))
        editablePattern.sharpnessCurve[idx].value = max(0, min(1, value))
    }

    // MARK: - 瞬态编辑

    func addTransient(at time: TimeInterval) {
        let t = EditableTransient(time: max(0, min(duration, time)), intensity: 0.8, sharpness: 0.5)
        editablePattern.transients.append(t)
        editablePattern.transients.sort { $0.time < $1.time }
    }

    func moveTransient(id: UUID, toTime time: TimeInterval) {
        guard let idx = editablePattern.transients.firstIndex(where: { $0.id == id }) else { return }
        editablePattern.transients[idx].time = max(0, min(duration, time))
    }

    func deleteTransient(id: UUID) {
        editablePattern.transients.removeAll { $0.id == id }
        if selectedTransientID == id { selectedTransientID = nil }
    }

    func selectTransient(id: UUID) {
        selectedTransientID = (selectedTransientID == id) ? nil : id
    }

    func updateTransient(id: UUID, intensity: Float, sharpness: Float) {
        guard let idx = editablePattern.transients.firstIndex(where: { $0.id == id }) else { return }
        editablePattern.transients[idx].intensity = max(0, min(1, intensity))
        editablePattern.transients[idx].sharpness = max(0, min(1, sharpness))
    }

    // MARK: - 权重区域编辑（修改后触发重新生成）

    func addRegion(startTime: TimeInterval, endTime: TimeInterval) {
        let newRegion = WeightRegion(
            startTime: startTime,
            endTime: endTime,
            mapping: regionMapping.defaultMapping
        )
        regionMapping.addRegion(newRegion)
        selectedRegionID = newRegion.id
        scheduleRegeneration()
    }

    func deleteRegion(id: UUID) {
        regionMapping.removeRegion(id: id)
        if selectedRegionID == id { selectedRegionID = nil }
        scheduleRegeneration()
    }

    func resizeRegion(id: UUID, newStart: TimeInterval?, newEnd: TimeInterval?) {
        regionMapping.resizeRegion(id: id, newStart: newStart, newEnd: newEnd)
        scheduleRegeneration()
    }

    func updateRegionMapping(id: UUID, mapping: ChannelMapping) {
        guard let idx = regionMapping.regions.firstIndex(where: { $0.id == id }) else { return }
        regionMapping.regions[idx].mapping = mapping
        scheduleRegeneration()
    }

    func selectRegion(id: UUID) {
        selectedRegionID = (selectedRegionID == id) ? nil : id
    }

    // MARK: - 播放

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }

        let descriptor = editablePattern.toDescriptor()
        do {
            let pattern = try exporter.makePattern(descriptor)
            try player.prepare(audioURL: audioURL, pattern: pattern)
            try player.seek(to: playbackTime)
            try player.play()
            isPlaying = true
            startPlaybackTimer()
        } catch {
            isPlaying = false
        }
    }

    func stopPlayback() {
        player.stop()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackTime = 0
    }

    func seekPlayback(to time: TimeInterval) {
        playbackTime = max(0, min(duration, time))
        if isPlaying {
            try? player.seek(to: playbackTime)
        }
    }

    // MARK: - 应用结果到 ProjectViewModel

    func applyChanges(to projectVM: ProjectViewModel) {
        let descriptor = editablePattern.toDescriptor()
        projectVM.patternDescriptor = descriptor
        if let pattern = try? exporter.makePattern(descriptor) {
            projectVM.generatedPattern = pattern
        }
    }

    // MARK: - 私有

    private func scheduleRegeneration() {
        regenerateTask?.cancel()
        regenerateTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                let descriptor = try self.generator.generate(
                    from: self.analysisResult,
                    regionMapping: self.regionMapping,
                    settings: self.settings
                )
                self.editablePattern = EditableHapticPattern(from: descriptor)
            } catch {
                // 忽略重新生成失败（继续使用当前 editablePattern）
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                // AVAudioPlayer 已是同步属性，直接读取
                if let time = self.player.currentTime {
                    self.playbackTime = time
                    if time >= self.duration {
                        self.stopPlayback()
                    }
                }
            }
        }
    }
}
