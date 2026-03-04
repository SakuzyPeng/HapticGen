import SwiftUI

/// 编辑器顶部工具栏：关闭按钮 | 工具切换 | 缩放滑块
struct EditorToolbarView: View {
    @ObservedObject var editorVM: TimelineEditorViewModel
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // 关闭
            Button {
                onClose?()
            } label: {
                Image(systemName: "chevron.left")
                Text(L10n.editorButtonClose)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.accentColor)

            Spacer()

            // 工具切换
            Picker("", selection: $editorVM.currentTool) {
                ForEach(TimelineEditorViewModel.EditorTool.allCases, id: \.self) { tool in
                    Image(systemName: tool.systemImage)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Spacer()

            // 缩放
            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.secondary)
                Slider(
                    value: $editorVM.zoom,
                    in: 0.25...4.0
                )
                .frame(width: 100)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
