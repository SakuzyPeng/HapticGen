import SwiftUI
import UniformTypeIdentifiers

struct DebugDashboardView: View {
    @StateObject private var viewModel = ProjectViewModel()
    @AppStorage(AppLanguage.storageKey) private var languageOverrideRawValue: String = AppLanguage.auto.rawValue
    @State private var isImporterPresented = false
    @State private var isPackaging = false

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage.resolved(rawValue: languageOverrideRawValue) },
            set: { languageOverrideRawValue = $0.rawValue }
        )
    }

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
            .navigationTitle(L10n.debugNavigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(L10n.languageMenuTitle, selection: languageSelection) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(L10n.languageOption(language)).tag(language)
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                }
            }
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
            .alert(L10n.commonAlertErrorTitle, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
                Button(L10n.commonButtonOK, role: .cancel) {
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
        GroupBox(L10n.debugSectionImport) {
            VStack(alignment: .leading, spacing: 10) {
                Button(L10n.debugButtonImportAudio) {
                    isImporterPresented = true
                }
                .buttonStyle(.borderedProminent)

                Text(L10n.debugFile(viewModel.fileName))
                Text(L10n.debugChannel(viewModel.channelCount))
                Text(L10n.debugDuration(viewModel.durationText))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionSection: some View {
        GroupBox(L10n.debugSectionAction) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(L10n.debugButtonAnalyze) {
                        viewModel.analyzeAudio()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing || viewModel.selectedAudioURL == nil)

                    Button(L10n.debugButtonGenerate) {
                        viewModel.generatePattern()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.analysisResult == nil || viewModel.isGenerating)
                }

                HStack(spacing: 8) {
                    Button(viewModel.isPlaying ? L10n.debugButtonPause : L10n.debugButtonPlay) {
                        viewModel.togglePlayback()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.patternDescriptor == nil)

                    Button(L10n.debugButtonStop) {
                        viewModel.stopPlayback()
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.debugButtonExportAHAP) {
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
                        Text(L10n.debugButtonPackageTrailer)
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
        GroupBox(L10n.debugSectionParameters) {
            VStack(alignment: .leading, spacing: 12) {
                sliderRow(
                    title: L10n.debugSliderIntensityScale,
                    value: Binding(
                        get: { Double(viewModel.settings.intensityScale) },
                        set: { viewModel.updateIntensityScale(Float($0)) }
                    ),
                    range: 0.2...2.0
                )

                sliderRow(
                    title: L10n.debugSliderSharpnessBias,
                    value: Binding(
                        get: { Double(viewModel.settings.sharpnessBias) },
                        set: { viewModel.updateSharpnessBias(Float($0)) }
                    ),
                    range: -0.5...0.5
                )

                sliderRow(
                    title: L10n.debugSliderEventDensity,
                    value: Binding(
                        get: { Double(viewModel.settings.eventDensity) },
                        set: { viewModel.updateEventDensity(Float($0)) }
                    ),
                    range: 0.2...3.0
                )

                sliderRow(
                    title: L10n.debugSliderTransientSensitivity,
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
        GroupBox(L10n.debugSectionResult) {
            VStack(alignment: .leading, spacing: 8) {
                if let analysis = viewModel.analysisResult {
                    let totalFrames = analysis.channels.first?.frames.count ?? 0
                    Text(L10n.debugAnalysisFrames(totalFrames))
                    Text(L10n.debugLayout(analysis.layout.channelCount))
                    if let diagnostics = viewModel.strategyDiagnostics {
                        Text(
                            L10n.debugStrategyRatio(
                                kick: diagnostics.kickLeadRatio,
                                vocal: diagnostics.vocalLeadRatio,
                                balanced: diagnostics.balancedRatio
                            )
                        )
                        Text(L10n.debugLFEAvailable(diagnostics.lfeAvailable))
                        if !diagnostics.fallbackReasons.isEmpty {
                            Text(L10n.debugFallback(diagnostics.fallbackReasons.joined(separator: ", ")))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(L10n.debugAnalysisFramesEmpty)
                }

                if let descriptor = viewModel.patternDescriptor {
                    Text(L10n.debugTransientCount(descriptor.transientEvents.count))
                    Text(L10n.debugIntensityPoints(descriptor.intensityCurvePoints.count))
                    Text(L10n.debugSharpnessPoints(descriptor.sharpnessCurvePoints.count))
                } else {
                    Text(L10n.debugTransientCountEmpty)
                    Text(L10n.debugCurvePointsEmpty)
                }

                Text(L10n.debugExportPath(viewModel.exportedAHAPPath))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusSection: some View {
        GroupBox(L10n.debugSectionStatus) {
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
