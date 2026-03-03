import SwiftUI
import UniformTypeIdentifiers

struct DebugDashboardView: View {
    @StateObject private var viewModel = ProjectViewModel()
    @State private var isImporterPresented = false
    @State private var isPackaging = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    importSection
                    actionSection
                    sliderSection
                    resultSection
                    statusSection
                }
                .padding(16)
            }
            .navigationTitle("AudioHaptic Debug")
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let first = urls.first {
                        viewModel.importAudio(url: first)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .alert("错误", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
                Button("确定", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $viewModel.showTrailerPlayer) {
                if let zipURL = viewModel.trailerZipURL {
                    HapticTrailerPlayerView(zipURL: zipURL)
                }
            }
        }
    }

    private var importSection: some View {
        GroupBox("导入") {
            VStack(alignment: .leading, spacing: 10) {
                Button("导入音频") {
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)

                Text("文件：\(viewModel.fileName)")
                Text("声道：\(viewModel.channelCount)")
                Text("时长：\(viewModel.durationText)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionSection: some View {
        GroupBox("操作") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("Analyze") {
                        viewModel.analyzeAudio()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing || viewModel.selectedAudioURL == nil)

                    Button("Generate") {
                        viewModel.generatePattern()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.analysisResult == nil || viewModel.isGenerating)
                }

                HStack(spacing: 8) {
                    Button(viewModel.isPlaying ? "Pause" : "Play") {
                        viewModel.togglePlayback()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.patternDescriptor == nil)

                    Button("Stop") {
                        viewModel.stopPlayback()
                    }
                    .buttonStyle(.bordered)

                    Button("Export .ahap") {
                        viewModel.exportAHAP()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.patternDescriptor == nil)
                }

                Button {
                    isPackaging = true
                    Task {
                        await viewModel.packageHapticTrailer()
                        isPackaging = false
                    }
                } label: {
                    HStack {
                        if isPackaging {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Package Haptic Trailer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(viewModel.patternDescriptor == nil || isPackaging)

                if viewModel.isAnalyzing {
                    ProgressView(value: viewModel.analysisProgress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sliderSection: some View {
        GroupBox("参数") {
            VStack(alignment: .leading, spacing: 12) {
                sliderRow(
                    title: "强度倍率",
                    value: Binding(
                        get: { Double(viewModel.settings.intensityScale) },
                        set: { viewModel.updateIntensityScale(Float($0)) }
                    ),
                    range: 0.2...2.0
                )

                sliderRow(
                    title: "清晰度偏移",
                    value: Binding(
                        get: { Double(viewModel.settings.sharpnessBias) },
                        set: { viewModel.updateSharpnessBias(Float($0)) }
                    ),
                    range: -0.5...0.5
                )

                sliderRow(
                    title: "事件密度",
                    value: Binding(
                        get: { Double(viewModel.settings.eventDensity) },
                        set: { viewModel.updateEventDensity(Float($0)) }
                    ),
                    range: 0.2...3.0
                )

                sliderRow(
                    title: "瞬态灵敏度",
                    value: Binding(
                        get: { Double(viewModel.settings.transientSensitivity) },
                        set: { viewModel.updateTransientSensitivity(Float($0)) }
                    ),
                    range: 0...1.0
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultSection: some View {
        GroupBox("结果") {
            VStack(alignment: .leading, spacing: 8) {
                if let analysis = viewModel.analysisResult {
                    let totalFrames = analysis.channels.first?.frames.count ?? 0
                    Text("分析帧数：\(totalFrames)")
                    Text("布局：\(analysis.layout.channelCount)ch")
                } else {
                    Text("分析帧数：-")
                }

                if let descriptor = viewModel.patternDescriptor {
                    Text("瞬态数量：\(descriptor.transientEvents.count)")
                    Text("Intensity 点数：\(descriptor.intensityCurvePoints.count)")
                    Text("Sharpness 点数：\(descriptor.sharpnessCurvePoints.count)")
                } else {
                    Text("瞬态数量：-")
                    Text("曲线点数：-")
                }

                Text("导出路径：\(viewModel.exportedAHAPPath)")
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusSection: some View {
        GroupBox("状态") {
            Text(viewModel.statusMessage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}
