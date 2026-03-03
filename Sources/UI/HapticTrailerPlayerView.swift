import SwiftUI
import CoreHaptics

struct HapticTrailerPlayerView: View {
    let zipURL: URL

    @State private var player = HapticTrailerPlayer()
    @State private var isPlaying = false
    @State private var progress: TimeInterval = 0
    @State private var isLoaded = false
    @State private var errorMessage: String?

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    packageInfoSection
                    playbackSection
                    shareSection
                }
                .padding(16)
            }
            .navigationTitle("Haptic Trailer")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadPlayer() }
            .onDisappear { player.stop() }
            .onReceive(ticker) { _ in
                guard isLoaded else { return }
                progress = player.audioCurrentTime
                if isPlaying && !player.isPlaying {
                    isPlaying = false
                }
            }
            .alert("错误", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var packageInfoSection: some View {
        GroupBox("包信息") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "文件", value: zipURL.lastPathComponent)
                infoRow(label: "HLS 标签", value: "com.apple.hls.haptics.url")
                infoRow(
                    label: "触觉支持",
                    value: CHHapticEngine.capabilitiesForHardware().supportsHaptics
                        ? "✓ 支持（真机）"
                        : "✗ 不支持（模拟器）"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var playbackSection: some View {
        GroupBox("播放控制") {
            VStack(spacing: 12) {
                let duration = player.audioDuration

                ProgressView(value: duration > 0 ? progress / duration : 0)

                HStack {
                    Text(formatTime(progress))
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(duration))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 32) {
                    Button { seek(by: -10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
                    }
                    .disabled(!isLoaded)

                    Button { togglePlayback() } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    .disabled(!isLoaded)

                    Button { seek(by: 10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                    }
                    .disabled(!isLoaded)
                }
                .frame(maxWidth: .infinity)

                if !isLoaded {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var shareSection: some View {
        GroupBox("导出") {
            VStack(alignment: .leading, spacing: 10) {
                ShareLink("分享 Haptic Trailer 包", item: zipURL)
                    .buttonStyle(.borderedProminent)

                Text("zip 包内含清单、AHAP 和音频，接收方用本 App 打开即可播放。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func loadPlayer() async {
        do {
            try player.load(manifestURL: zipURL)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            do {
                try player.play()
                isPlaying = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func seek(by delta: TimeInterval) {
        let target = max(0, min(player.audioDuration, progress + delta))
        do {
            try player.seek(to: target)
            progress = target
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
