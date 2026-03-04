import SwiftUI

/// 多轨道时间轴触觉编辑器主页面（全屏，Generate 后 push 进入）
struct TimelineEditorView: View {
    @ObservedObject var projectVM: ProjectViewModel
    @StateObject private var editorVM: TimelineEditorViewModel

    init(projectVM: ProjectViewModel) {
        self.projectVM = projectVM
        guard
            let pattern = projectVM.patternDescriptor,
            let analysis = projectVM.analysisResult,
            let audioURL = projectVM.selectedAudioURL
        else {
            // 防御性初始化（正常路径不会走到这里）
            let fallback = TimelineEditorViewModel(
                pattern: HapticPatternDescriptor(
                    duration: 1,
                    continuousEvent: ContinuousEventDescriptor(duration: 1),
                    intensityCurvePoints: [],
                    sharpnessCurvePoints: [],
                    transientEvents: []
                ),
                analysisResult: MultiChannelAnalysisResult(
                    duration: 1,
                    sampleRate: 44100,
                    layout: ChannelLayout.detect(channelCount: 2),
                    channels: []
                ),
                mapping: ChannelMapping(intensity: [], sharpness: [], transient: []),
                settings: GeneratorSettings(),
                audioURL: URL(filePath: "/dev/null")
            )
            self._editorVM = StateObject(wrappedValue: fallback)
            return
        }
        self._editorVM = StateObject(wrappedValue: TimelineEditorViewModel(
            pattern: pattern,
            analysisResult: analysis,
            mapping: projectVM.mapping,
            settings: projectVM.settings,
            audioURL: audioURL
        ))
    }

    // MARK: - 轨道高度常量
    private let rulerHeight: CGFloat = 30
    private let curveTrackHeight: CGFloat = 120
    private let transientTrackHeight: CGFloat = 60
    private let regionTrackHeight: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbarView(editorVM: editorVM) {
                applyAndDismiss()
            }

            Divider()

            GeometryReader { geometry in
                let totalWidth = editorVM.totalContentWidth(viewportWidth: geometry.size.width)

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        TimeRulerView(
                            duration: editorVM.duration,
                            totalWidth: totalWidth
                        )

                        Divider()

                        TimelineCanvasView(
                            title: L10n.editorTrackIntensity,
                            curve: editorVM.editablePattern.intensityCurve,
                            color: .orange,
                            duration: editorVM.duration,
                            totalWidth: totalWidth,
                            trackHeight: curveTrackHeight,
                            onPointMoved: { id, time, value in
                                editorVM.moveIntensityPoint(id: id, time: time, value: value)
                            }
                        )

                        Divider()

                        TimelineCanvasView(
                            title: L10n.editorTrackSharpness,
                            curve: editorVM.editablePattern.sharpnessCurve,
                            color: .cyan,
                            duration: editorVM.duration,
                            totalWidth: totalWidth,
                            trackHeight: curveTrackHeight,
                            onPointMoved: { id, time, value in
                                editorVM.moveSharpnessPoint(id: id, time: time, value: value)
                            }
                        )

                        Divider()

                        transientTrack(totalWidth: totalWidth)

                        Divider()

                        regionTrack(totalWidth: totalWidth)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // 播放头竖线
                    let x = editorVM.playheadX(totalWidth: totalWidth)
                    Rectangle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 2, height: totalTrackHeight)
                        .offset(x: x)
                        .allowsHitTesting(false)
                }
            }

            Divider()

            EditorTransportBar(editorVM: editorVM)

            // 选中瞬态时显示参数编辑面板
            if let selectedID = editorVM.selectedTransientID,
               let transient = editorVM.editablePattern.transients.first(where: { $0.id == selectedID }) {
                Divider()
                transientParamPanel(transient: transient)
            }

            // 选中权重区域时显示区域编辑面板
            if let selectedID = editorVM.selectedRegionID,
               let region = editorVM.regionMapping.regions.first(where: { $0.id == selectedID }) {
                Divider()
                regionParamPanel(region: region)
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            editorVM.stopPlayback()
            editorVM.applyChanges(to: projectVM)
        }
    }

    // MARK: - 瞬态轨道

    private func transientTrack(totalWidth: CGFloat) -> some View {
        TransientTrackView(
            transients: editorVM.editablePattern.transients,
            duration: editorVM.duration,
            totalWidth: totalWidth,
            trackHeight: transientTrackHeight,
            currentTool: editorVM.currentTool,
            onTap: { x in
                let time = editorVM.xToTime(x, totalWidth: totalWidth)
                if editorVM.currentTool == .addTransient {
                    editorVM.addTransient(at: time)
                } else {
                    // 选中最近的瞬态
                    if let nearest = editorVM.editablePattern.transients.min(by: {
                        abs($0.time - time) < abs($1.time - time)
                    }), abs(nearest.time - time) < 0.5 {
                        editorVM.selectTransient(id: nearest.id)
                    }
                }
            },
            onLongPress: { id in
                editorVM.deleteTransient(id: id)
            },
            selectedID: editorVM.selectedTransientID
        )
    }

    // MARK: - 权重区域轨道

    private func regionTrack(totalWidth: CGFloat) -> some View {
        WeightRegionTrackView(
            regionMapping: editorVM.regionMapping,
            channelLabels: editorVM.channelLabels,
            duration: editorVM.duration,
            totalWidth: totalWidth,
            trackHeight: regionTrackHeight,
            selectedRegionID: editorVM.selectedRegionID,
            onRegionTapped: { id in
                editorVM.selectRegion(id: id)
            },
            onRegionResized: { id, newStart, newEnd in
                editorVM.resizeRegion(id: id, newStart: newStart, newEnd: newEnd)
            },
            onAddRegion: { start, end in
                editorVM.addRegion(startTime: start, endTime: end)
            }
        )
    }

    // MARK: - 瞬态参数编辑面板

    private func transientParamPanel(transient: EditableTransient) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(format: "%.3fs", transient.time))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(role: .destructive) {
                    editorVM.deleteTransient(id: transient.id)
                } label: {
                    Image(systemName: "trash")
                }
                .font(.caption)
            }

            HStack {
                Text("Intensity")
                    .font(.caption)
                    .frame(width: 70, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(transient.intensity) },
                        set: { editorVM.updateTransient(id: transient.id, intensity: Float($0), sharpness: transient.sharpness) }
                    ),
                    in: 0...1
                )
                Text(String(format: "%.2f", transient.intensity))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 35, alignment: .trailing)
            }

            HStack {
                Text("Sharpness")
                    .font(.caption)
                    .frame(width: 70, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(transient.sharpness) },
                        set: { editorVM.updateTransient(id: transient.id, intensity: transient.intensity, sharpness: Float($0)) }
                    ),
                    in: 0...1
                )
                Text(String(format: "%.2f", transient.sharpness))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemBackground))
    }

    // MARK: - 权重区域参数编辑面板

    private func regionParamPanel(region: WeightRegion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(format: "%.2fs – %.2fs", region.startTime, region.endTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(role: .destructive) {
                    editorVM.deleteRegion(id: region.id)
                } label: {
                    Image(systemName: "trash")
                }
                .font(.caption)
            }

            Text("Intensity weights")
                .font(.caption2).foregroundColor(.secondary)

            ForEach(editorVM.channelLabels, id: \.self) { label in
                channelWeightRow(
                    label: label,
                    feature: .intensity,
                    region: region
                )
            }

            Text("Sharpness weights")
                .font(.caption2).foregroundColor(.secondary)

            ForEach(editorVM.channelLabels, id: \.self) { label in
                channelWeightRow(
                    label: label,
                    feature: .sharpness,
                    region: region
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemBackground))
    }

    private func channelWeightRow(label: String, feature: HapticFeature, region: WeightRegion) -> some View {
        let currentWeight = region.mapping.weights(for: feature)
            .first(where: { $0.channelLabel == label })?.weight ?? 0

        return HStack {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 36, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(currentWeight) },
                    set: { newValue in
                        var updated = region.mapping
                        var weights: [ChannelWeight]
                        switch feature {
                        case .intensity:
                            weights = updated.intensity.filter { $0.channelLabel != label }
                            if newValue > 0 { weights.append(ChannelWeight(channelLabel: label, weight: Float(newValue))) }
                            updated = ChannelMapping(intensity: weights, sharpness: updated.sharpness, transient: updated.transient)
                        case .sharpness:
                            weights = updated.sharpness.filter { $0.channelLabel != label }
                            if newValue > 0 { weights.append(ChannelWeight(channelLabel: label, weight: Float(newValue))) }
                            updated = ChannelMapping(intensity: updated.intensity, sharpness: weights, transient: updated.transient)
                        case .transient:
                            weights = updated.transient.filter { $0.channelLabel != label }
                            if newValue > 0 { weights.append(ChannelWeight(channelLabel: label, weight: Float(newValue))) }
                            updated = ChannelMapping(intensity: updated.intensity, sharpness: updated.sharpness, transient: weights)
                        }
                        editorVM.updateRegionMapping(id: region.id, mapping: updated)
                    }
                ),
                in: 0...1
            )
            Text(String(format: "%.2f", currentWeight))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - 辅助

    private var totalTrackHeight: CGFloat {
        rulerHeight + curveTrackHeight * 2 + transientTrackHeight + regionTrackHeight
    }

    private func dominantChannelLabel(for mapping: ChannelMapping) -> String {
        let allWeights = mapping.intensity + mapping.sharpness + mapping.transient
        guard let top = allWeights.max(by: { $0.weight < $1.weight }) else {
            return L10n.editorDefaultRegionLabel
        }
        return top.channelLabel
    }

    private func applyAndDismiss() {
        editorVM.stopPlayback()
        editorVM.applyChanges(to: projectVM)
        projectVM.showEditor = false
    }
}

@MainActor private func makePreviewVM() -> ProjectViewModel {
    var frames: [ChannelFeatureFrame] = []
    for i in 0..<300 {
        let t = Double(i) / 30.0
        let rms = Float(sin(t * 3.14) * 0.5 + 0.5)
        let sc = Float(cos(t * 2.0) * 0.4 + 0.5)
        let tr: Float = i % 30 == 0 ? 0.9 : 0.05
        frames.append(ChannelFeatureFrame(time: t, rms: rms, spectralCentroidNorm: sc, transientStrength: tr, isTransient: i % 30 == 0))
    }
    let layout = ChannelLayout.detect(channelCount: 2)
    let analysis = MultiChannelAnalysisResult(
        duration: 10.0, sampleRate: 44100, layout: layout,
        channels: [ChannelAnalysisResult(label: "L", frames: frames), ChannelAnalysisResult(label: "R", frames: frames)]
    )
    let mapping = ChannelMapping.defaults(for: layout)
    let descriptor = try! HapticGenerator().generate(from: analysis, mapping: mapping, settings: GeneratorSettings())
    let vm = ProjectViewModel()
    vm.patternDescriptor = descriptor
    vm.analysisResult = analysis
    vm.mapping = mapping
    vm.selectedAudioURL = URL(filePath: "/dev/null")
    return vm
}

#Preview {
    TimelineEditorView(projectVM: makePreviewVM())
}
