import SwiftUI

/// 编辑器底部播放控制条
struct EditorTransportBar: View {
    @ObservedObject var editorVM: TimelineEditorViewModel

    var body: some View {
        HStack(spacing: 20) {
            // 播放/暂停按钮
            Button {
                editorVM.togglePlayback()
            } label: {
                Image(systemName: editorVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            // 停止
            Button {
                editorVM.stopPlayback()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // 时间显示
            Text(formatTime(editorVM.playbackTime))
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .leading)

            Text("/")
                .foregroundColor(.secondary)

            Text(formatTime(editorVM.duration))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", m, s, ms)
    }
}
