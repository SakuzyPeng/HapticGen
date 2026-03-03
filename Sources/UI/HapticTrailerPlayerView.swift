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
            .navigationTitle(L10n.playerNavigationTitle)
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
            .alert(L10n.commonAlertErrorTitle, isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(L10n.commonButtonOK, role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var packageInfoSection: some View {
        GroupBox(L10n.playerSectionPackageInfo) {
            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: L10n.playerInfoFile, value: zipURL.lastPathComponent)
                infoRow(label: L10n.playerInfoHLSTag, value: "com.apple.hls.haptics.url")
                infoRow(
                    label: L10n.playerInfoHapticsSupport,
                    value: CHHapticEngine.capabilitiesForHardware().supportsHaptics
                        ? L10n.playerInfoHapticsSupported
                        : L10n.playerInfoHapticsUnsupported
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var playbackSection: some View {
        GroupBox(L10n.playerSectionPlayback) {
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
                    ProgressView(L10n.playerLoading)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var shareSection: some View {
        GroupBox(L10n.playerSectionExport) {
            VStack(alignment: .leading, spacing: 10) {
                ShareLink(L10n.playerShareButton, item: zipURL)
                    .buttonStyle(.borderedProminent)

                Text(L10n.playerShareDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
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
