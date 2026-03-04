import SwiftUI

/// 瞬态事件轨道：竖线标记，支持添加、选中、删除
struct TransientTrackView: View {
    let transients: [EditableTransient]
    let duration: TimeInterval
    let totalWidth: CGFloat
    let trackHeight: CGFloat
    let currentTool: TimelineEditorViewModel.EditorTool

    var onTap: ((CGFloat) -> Void)?        // 点击位置的 x 坐标（用于添加或选中）
    var onLongPress: ((UUID) -> Void)?     // 长按瞬态 id（用于删除）
    var selectedID: UUID?

    @State private var lastPressX: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(L10n.editorTrackTransients)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
                .zIndex(1)

            Canvas { context, size in
                // 背景
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(uiColor: .systemBackground))
                )

                guard duration > 0 else { return }

                for transient in transients {
                    let x = CGFloat(transient.time / duration) * size.width
                    let h = size.height * CGFloat(transient.intensity)
                    let y = size.height - h
                    let isSelected = transient.id == selectedID

                    // 竖线
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x, y: y))
                    context.stroke(
                        path,
                        with: .color(isSelected ? .yellow : .purple.opacity(0.7)),
                        lineWidth: isSelected ? 2.5 : 1.5
                    )

                    // 顶部圆圈
                    let r: CGFloat = isSelected ? 6 : 4
                    let dot = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: dot), with: .color(isSelected ? .yellow : .purple))
                }
            }
            .frame(width: totalWidth, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        lastPressX = value.location.x
                    }
            )
            .onTapGesture { location in
                onTap?(location.x)
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                if let id = nearestTransientID(at: lastPressX) {
                    onLongPress?(id)
                }
            }
        }
        .frame(width: totalWidth, height: trackHeight)
    }

    private func nearestTransientID(at x: CGFloat) -> UUID? {
        guard duration > 0 else { return nil }
        let hitRadius: CGFloat = 20
        var closest: UUID?
        var closestDist: CGFloat = .greatestFiniteMagnitude
        for t in transients {
            let tx = CGFloat(t.time / duration) * totalWidth
            let dist = abs(x - tx)
            if dist < hitRadius && dist < closestDist {
                closestDist = dist
                closest = t.id
            }
        }
        return closest
    }
}
