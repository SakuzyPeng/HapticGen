import SwiftUI
import UniformTypeIdentifiers

struct TimelineEditorView: View {
    @StateObject private var viewModel = TimelineEditorViewModel()
    @State private var isImporterPresented = false
    @State private var curveInputIntensity: Double = 0.7
    @State private var curveInputSharpness: Double = 0.5
    @State private var customChannelInput = ""
    @State private var pinchScaleValue: CGFloat = 1

    private let laneHeight: CGFloat = 74
    private let headerWidth: CGFloat = 130

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                topBar
                timelineArea
                inspector
                statusBar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .navigationTitle("Timeline Editor")
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
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Import") { isImporterPresented = true }
                    .buttonStyle(.borderedProminent)

                Button("Analyze") { viewModel.analyzeAudio() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.selectedAudioURL == nil || viewModel.isAnalyzing)

                Button(viewModel.isPlaying ? "Pause" : "Play") { viewModel.togglePlayback() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.timelineDocument == nil)

                Button("Stop") { viewModel.stopPlayback() }
                    .buttonStyle(.bordered)

                Button("Export") { viewModel.exportAHAP() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.timelineDocument == nil)
            }

            HStack(spacing: 8) {
                Picker("Template", selection: Binding(
                    get: { viewModel.selectedTemplate },
                    set: { viewModel.applyTemplate($0) }
                )) {
                    ForEach(TimelineTemplate.allCases, id: \.self) { template in
                        Text(template.rawValue.capitalized).tag(template)
                    }
                }
                .pickerStyle(.segmented)

                Button("+ Track") {
                    viewModel.addTrack()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Text("\(viewModel.fileName) • \(viewModel.channelCount)ch • \(viewModel.durationText)")
                    .font(.caption)
                    .lineLimit(1)

                Spacer()

                Text(String(format: "T %.2fs", viewModel.playhead))
                    .font(.caption.monospacedDigit())

                HStack(spacing: 6) {
                    Text("Zoom")
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.zoomScale) },
                            set: { value in
                                let current = viewModel.zoomScale
                                let target = CGFloat(value)
                                let factor = max(0.1, target / max(current, 1))
                                viewModel.updateZoom(factor)
                            }
                        ),
                        in: 40...240
                    )
                    .frame(width: 120)
                }
            }

            if viewModel.isAnalyzing {
                ProgressView(value: viewModel.analysisProgress)
            }
        }
    }

    private var timelineArea: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 8) {
                if let document = viewModel.timelineDocument {
                    ForEach(document.tracks) { track in
                        trackRow(track)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 120)
                        .overlay {
                            Text("Analyze audio to create timeline tracks")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 240)
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { scale in
                    let delta = max(0.25, min(4, scale / max(pinchScaleValue, 0.01)))
                    viewModel.updateZoom(delta)
                    pinchScaleValue = scale
                }
                .onEnded { _ in
                    pinchScaleValue = 1
                }
        )
    }

    private func trackRow(_ track: HapticTrack) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(track.name)
                    .font(.caption.bold())
                HStack(spacing: 4) {
                    Button(track.isMuted ? "M*" : "M") {
                        viewModel.setTrackMuted(!track.isMuted, trackID: track.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button(track.isSolo ? "S*" : "S") {
                        viewModel.setTrackSolo(!track.isSolo, trackID: track.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("+Clip") {
                        viewModel.select(trackID: track.id, clipID: nil)
                        viewModel.addClip(to: track.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .frame(width: headerWidth, alignment: .leading)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let seconds = max(Int(viewModel.timelineDuration.rounded()), 1)
                    for sec in 0...seconds {
                        let x = CGFloat(sec) * viewModel.zoomScale
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        let color = sec % 5 == 0 ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.15)
                        context.stroke(path, with: .color(color), lineWidth: sec % 5 == 0 ? 1 : 0.5)
                    }
                }
                .frame(width: viewModel.timelineWidth, height: laneHeight)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let t = TimeInterval(max(0, min(viewModel.timelineWidth, value.location.x)) / max(viewModel.zoomScale, 1))
                            viewModel.seek(to: t)
                        }
                )

                ForEach(track.clips) { clip in
                    clipView(track: track, clip: clip)
                }

                Rectangle()
                    .fill(.red)
                    .frame(width: 2, height: laneHeight)
                    .offset(x: CGFloat(viewModel.playhead) * viewModel.zoomScale)
            }
            .frame(width: viewModel.timelineWidth, height: laneHeight)
            .onLongPressGesture {
                viewModel.select(trackID: track.id, clipID: nil)
                viewModel.addClip(to: track.id)
            }
        }
    }

    private func clipView(track: HapticTrack, clip: TimelineClip) -> some View {
        let isSelected = viewModel.selectedTrackID == track.id && viewModel.selectedClipID == clip.id
        let x = CGFloat(clip.start) * viewModel.zoomScale
        let width = max(20, CGFloat(clip.duration) * viewModel.zoomScale)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.45) : Color.blue.opacity(0.28))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.blue.opacity(0.65), lineWidth: isSelected ? 2 : 1)
                }

            Canvas { context, size in
                let path = envelopePath(for: clip.intensityKeyframes, in: size)
                context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.2)
            }
            .padding(4)
        }
        .frame(width: width, height: laneHeight - 10)
        .offset(x: x, y: 5)
        .onTapGesture {
            viewModel.select(trackID: track.id, clipID: clip.id)
        }
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    let normalized = max(0, min(1, value.location.x / max(width, 1)))
                    viewModel.addIntensityKeyframe(
                        trackID: track.id,
                        clipID: clip.id,
                        normalizedTime: normalized
                    )
                }
        )
    }

    private func envelopePath(for keyframes: [TrackKeyframe], in size: CGSize) -> Path {
        guard !keyframes.isEmpty else { return Path() }
        let sorted = keyframes.sorted { $0.time < $1.time }

        var path = Path()
        for (index, key) in sorted.enumerated() {
            let x = CGFloat(max(0, min(1, key.time))) * size.width
            let y = (1 - CGFloat(key.value)) * size.height

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private var inspector: some View {
        GroupBox("Inspector") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Tab", selection: $viewModel.inspectorTab) {
                    ForEach(TimelineEditorViewModel.InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch viewModel.inspectorTab {
                case .source:
                    sourceInspector
                case .haptic:
                    hapticInspector
                case .curve:
                    curveInspector
                case .transient:
                    transientInspector
                case .channelMap:
                    channelMapInspector
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let track = viewModel.selectedTrack {
                Picker("Channel Group", selection: Binding(
                    get: { track.source.channelGroup.kind },
                    set: { viewModel.setTrackChannelGroupKind($0) }
                )) {
                    ForEach(ChannelGroupKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                Picker("Frequency Band", selection: Binding(
                    get: { track.source.frequencyBand.kind },
                    set: { viewModel.setTrackFrequencyBandKind($0) }
                )) {
                    ForEach(FrequencyBandKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                if track.source.frequencyBand.kind == .custom {
                    HStack {
                        Text("Min Hz")
                        Slider(
                            value: Binding(
                                get: { Double(track.source.frequencyBand.customMinHz) },
                                set: { viewModel.setCustomFrequency(minHz: Float($0), maxHz: track.source.frequencyBand.customMaxHz) }
                            ),
                            in: 20...6000
                        )
                        Text(String(format: "%.0f", track.source.frequencyBand.customMinHz))
                            .font(.caption.monospacedDigit())
                    }

                    HStack {
                        Text("Max Hz")
                        Slider(
                            value: Binding(
                                get: { Double(track.source.frequencyBand.customMaxHz) },
                                set: { viewModel.setCustomFrequency(minHz: track.source.frequencyBand.customMinHz, maxHz: Float($0)) }
                            ),
                            in: 20...12000
                        )
                        Text(String(format: "%.0f", track.source.frequencyBand.customMaxHz))
                            .font(.caption.monospacedDigit())
                    }
                }
            } else {
                Text("Select a track")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hapticInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let track = viewModel.selectedTrack {
                Picker("Style", selection: Binding(
                    get: { track.style },
                    set: { viewModel.setTrackStyle($0) }
                )) {
                    ForEach(TrackHapticStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Mix")
                    Slider(
                        value: Binding(
                            get: { Double(track.mixWeight) },
                            set: { viewModel.setTrackMixWeight(Float($0)) }
                        ),
                        in: 0...2
                    )
                    Text(String(format: "%.2f", track.mixWeight))
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Max Output")
                    Slider(
                        value: Binding(
                            get: { Double(track.maxOutput) },
                            set: { viewModel.setTrackMaxOutput(Float($0)) }
                        ),
                        in: 0...1
                    )
                    Text(String(format: "%.2f", track.maxOutput))
                        .font(.caption.monospacedDigit())
                }
            } else {
                Text("Select a track")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var curveInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let clip = viewModel.selectedClip {
                HStack {
                    Text("Start")
                    Slider(
                        value: Binding(
                            get: { clip.start },
                            set: { viewModel.setSelectedClipStart($0) }
                        ),
                        in: 0...max(0, viewModel.timelineDuration - 0.05)
                    )
                    Text(String(format: "%.2f", clip.start))
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Duration")
                    Slider(
                        value: Binding(
                            get: { clip.duration },
                            set: { viewModel.setSelectedClipDuration($0) }
                        ),
                        in: 0.05...max(0.05, viewModel.timelineDuration)
                    )
                    Text(String(format: "%.2f", clip.duration))
                        .font(.caption.monospacedDigit())
                }

                HStack(spacing: 8) {
                    Slider(value: $curveInputIntensity, in: 0...1)
                    Button("+ Intensity KF") {
                        viewModel.addIntensityKeyframeAtPlayhead(value: Float(curveInputIntensity))
                    }
                    .buttonStyle(.bordered)
                    Button("- Nearest") {
                        viewModel.removeNearestIntensityKeyframe()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Slider(value: $curveInputSharpness, in: 0...1)
                    Button("+ Sharpness KF") {
                        viewModel.addSharpnessKeyframeAtPlayhead(value: Float(curveInputSharpness))
                    }
                    .buttonStyle(.bordered)
                    Button("- Nearest") {
                        viewModel.removeNearestSharpnessKeyframe()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Remove Clip", role: .destructive) {
                    viewModel.removeSelectedClip()
                }
                .buttonStyle(.bordered)
            } else {
                Text("Select a clip")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transientInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let clip = viewModel.selectedClip {
                HStack {
                    Text("Threshold")
                    Slider(
                        value: Binding(
                            get: { Double(clip.transientRule.threshold) },
                            set: { viewModel.setTransientThreshold(Float($0)) }
                        ),
                        in: 0...1
                    )
                    Text(String(format: "%.2f", clip.transientRule.threshold))
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Cooldown")
                    Slider(
                        value: Binding(
                            get: { clip.transientRule.cooldown },
                            set: { viewModel.setTransientCooldown($0) }
                        ),
                        in: 0...0.2
                    )
                    Text(String(format: "%.3f", clip.transientRule.cooldown))
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Gain")
                    Slider(
                        value: Binding(
                            get: { Double(clip.transientRule.gain) },
                            set: { viewModel.setTransientGain(Float($0)) }
                        ),
                        in: 0...2
                    )
                    Text(String(format: "%.2f", clip.transientRule.gain))
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Pulse Rate")
                    Slider(
                        value: Binding(
                            get: { Double(clip.pulseRate) },
                            set: { viewModel.setPulseRate(Float($0)) }
                        ),
                        in: 0.5...20
                    )
                    Text(String(format: "%.1f", clip.pulseRate))
                        .font(.caption.monospacedDigit())
                }

                HStack {
                    Text("Pulse Depth")
                    Slider(
                        value: Binding(
                            get: { Double(clip.pulseDepth) },
                            set: { viewModel.setPulseDepth(Float($0)) }
                        ),
                        in: 0...1
                    )
                    Text(String(format: "%.2f", clip.pulseDepth))
                        .font(.caption.monospacedDigit())
                }
            } else {
                Text("Select a clip")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var channelMapInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let track = viewModel.selectedTrack {
                Text("Custom labels (comma-separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "e.g. L,R,C,LFE",
                    text: Binding(
                        get: {
                            if customChannelInput.isEmpty {
                                return track.source.channelGroup.customLabels.joined(separator: ",")
                            }
                            return customChannelInput
                        },
                        set: { customChannelInput = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)

                Button("Apply Custom Channel Map") {
                    viewModel.setCustomChannelLabels(customChannelInput)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Select a track")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusBar: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.statusMessage)
                Text("Export: \(viewModel.exportedAHAPPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
