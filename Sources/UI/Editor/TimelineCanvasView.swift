import SwiftUI

/// 单条曲线轨道，使用 Canvas 渲染 intensity 或 sharpness 曲线
struct TimelineCanvasView: View {
    let title: String
    let curve: [EditableCurvePoint]
    let color: Color
    let duration: TimeInterval
    let totalWidth: CGFloat
    let trackHeight: CGFloat

    /// 拖拽移动控制点（id, newTime, newValue）
    var onPointMoved: ((UUID, TimeInterval, Float) -> Void)?

    @State private var dragState: DragState? = nil

    private struct DragState {
        let id: UUID
    }

    private let hitRadius: CGFloat = 20
    private let pointRadius: CGFloat = 4

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 轨道标签
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
                .zIndex(1)

            Canvas { context, size in
                drawBackground(context: &context, size: size)
                drawGrid(context: &context, size: size)
                drawCurve(context: &context, size: size)
                drawControlPoints(context: &context, size: size)
            }
            .frame(width: totalWidth, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(width: totalWidth, height: trackHeight)
    }

    // MARK: - 绘制

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(uiColor: .systemBackground))
        )
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let gridColor = Color.secondary.opacity(0.12)
        // 水平网格线（0.25 / 0.5 / 0.75）
        for level in [0.25, 0.5, 0.75] as [CGFloat] {
            let y = size.height * (1 - level)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 1)
        }
    }

    private func drawCurve(context: inout GraphicsContext, size: CGSize) {
        let visible = visiblePoints(in: curve, size: size)
        guard visible.count >= 2 else { return }

        var path = Path()
        var first = true
        for point in visible {
            let pt = canvasPoint(point, size: size)
            if first {
                path.move(to: pt)
                first = false
            } else {
                path.addLine(to: pt)
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    private func drawControlPoints(context: inout GraphicsContext, size: CGSize) {
        let visible = visiblePoints(in: curve, size: size)
        guard !visible.isEmpty else { return }

        let pixelsPerPoint = visible.count > 1
            ? abs(canvasPoint(visible[visible.count - 1], size: size).x - canvasPoint(visible[0], size: size).x) / CGFloat(visible.count - 1)
            : totalWidth
        guard pixelsPerPoint >= 4 else { return }

        let stride = max(1, Int(4.0 / pixelsPerPoint))

        for (index, point) in visible.enumerated() {
            guard index % stride == 0 else { continue }
            let pt = canvasPoint(point, size: size)
            let isSelected = (dragState?.id == point.id)
            let r: CGFloat = isSelected ? pointRadius * 1.5 : pointRadius
            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(isSelected ? .white : color))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: isSelected ? 2 : 1)
        }
    }

    // MARK: - 坐标转换

    private func canvasPoint(_ point: EditableCurvePoint, size: CGSize) -> CGPoint {
        let x = duration > 0 ? CGFloat(point.time / duration) * size.width : 0
        let y = size.height * (1 - CGFloat(point.value))
        return CGPoint(x: x, y: y)
    }

    private func visiblePoints(in points: [EditableCurvePoint], size: CGSize) -> [EditableCurvePoint] {
        // 全部返回（Canvas 本身只渲染可见区域的像素，这里不做额外裁剪以保证曲线完整）
        points
    }

    private func nearestPoint(at location: CGPoint, size: CGSize) -> UUID? {
        var closest: UUID?
        var closestDist: CGFloat = .greatestFiniteMagnitude

        for point in curve {
            let pt = canvasPoint(point, size: CGSize(width: totalWidth, height: trackHeight))
            let dist = hypot(location.x - pt.x, location.y - pt.y)
            if dist < hitRadius && dist < closestDist {
                closestDist = dist
                closest = point.id
            }
        }
        return closest
    }

    // MARK: - 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragState == nil {
                    if let id = nearestPoint(at: value.startLocation,
                                             size: CGSize(width: totalWidth, height: trackHeight)) {
                        dragState = DragState(id: id)
                    }
                }
                if let id = dragState?.id {
                    let time = duration > 0
                        ? Double(value.location.x / totalWidth) * duration
                        : 0
                    let val = Float(1 - value.location.y / trackHeight)
                    onPointMoved?(id, time, val)
                }
            }
            .onEnded { _ in
                dragState = nil
            }
    }
}
