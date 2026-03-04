import SwiftUI

/// 声道权重区域轨道：彩色色块 + 拖拽边界调整大小
struct WeightRegionTrackView: View {
    let regionMapping: TimeRegionMapping
    let channelLabels: [String]
    let duration: TimeInterval
    let totalWidth: CGFloat
    let trackHeight: CGFloat
    let selectedRegionID: UUID?

    var onRegionTapped: ((UUID) -> Void)?
    var onRegionResized: ((UUID, TimeInterval?, TimeInterval?) -> Void)?
    var onAddRegion: ((TimeInterval, TimeInterval) -> Void)?

    // 记录拖拽的区域 ID 和拖拽侧（左/右边界）
    @State private var dragEdge: DragEdge? = nil

    private struct DragEdge {
        let regionID: UUID
        let side: Side
        enum Side { case start, end }
    }

    private let edgeHitWidth: CGFloat = 16  // 边界可拖拽的宽度
    private let regionColors: [Color] = [.indigo, .teal, .orange, .pink, .green, .blue]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(L10n.editorTrackRegions)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.indigo)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
                .zIndex(1)

            Canvas { context, size in
                drawBackground(context: &context, size: size)
                drawRegions(context: &context, size: size)
            }
            .frame(width: totalWidth, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(combinedGesture)
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

    private func drawRegions(context: inout GraphicsContext, size: CGSize) {
        guard duration > 0 else { return }

        for (index, region) in regionMapping.regions.enumerated() {
            let x1 = CGFloat(region.startTime / duration) * size.width
            let x2 = CGFloat(region.endTime / duration) * size.width
            let color = regionColors[index % regionColors.count]
            let isSelected = region.id == selectedRegionID

            // 色块主体
            let rect = CGRect(x: x1, y: 22, width: x2 - x1, height: size.height - 26)
            context.fill(Path(rect), with: .color(color.opacity(isSelected ? 0.4 : 0.2)))
            context.stroke(
                Path(rect),
                with: .color(color.opacity(isSelected ? 1.0 : 0.5)),
                lineWidth: isSelected ? 2 : 1
            )

            // 左右边界拖拽手柄
            for edgeX in [x1, x2] {
                let handleRect = CGRect(x: edgeX - 3, y: 22, width: 6, height: size.height - 26)
                context.fill(Path(handleRect), with: .color(color.opacity(0.7)))
            }

            // 区域标签（显示权重最高的声道名）
            if x2 - x1 > 40 {
                let label = dominantLabel(for: region.mapping)
                context.draw(
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(color),
                    in: CGRect(x: x1 + 8, y: 26, width: x2 - x1 - 16, height: 16)
                )
            }
        }
    }

    // MARK: - 手势

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragEdge == nil {
                    dragEdge = detectEdge(at: value.startLocation.x)
                }
                if let edge = dragEdge {
                    let newTime = duration > 0
                        ? max(0, min(duration, Double(value.location.x / totalWidth) * duration))
                        : 0
                    switch edge.side {
                    case .start:
                        onRegionResized?(edge.regionID, newTime, nil)
                    case .end:
                        onRegionResized?(edge.regionID, nil, newTime)
                    }
                }
            }
            .onEnded { _ in
                dragEdge = nil
            }
            .simultaneously(with:
                SpatialTapGesture()
                    .onEnded { value in
                        guard dragEdge == nil else { return }
                        let x = value.location.x
                        if let region = regionAt(x: x) {
                            onRegionTapped?(region.id)
                        }
                    }
            )
    }

    // MARK: - 辅助

    private func detectEdge(at x: CGFloat) -> DragEdge? {
        guard duration > 0 else { return nil }
        for region in regionMapping.regions {
            let x1 = CGFloat(region.startTime / duration) * totalWidth
            let x2 = CGFloat(region.endTime / duration) * totalWidth
            if abs(x - x1) < edgeHitWidth {
                return DragEdge(regionID: region.id, side: .start)
            }
            if abs(x - x2) < edgeHitWidth {
                return DragEdge(regionID: region.id, side: .end)
            }
        }
        return nil
    }

    private func regionAt(x: CGFloat) -> WeightRegion? {
        guard duration > 0 else { return nil }
        for region in regionMapping.regions {
            let x1 = CGFloat(region.startTime / duration) * totalWidth
            let x2 = CGFloat(region.endTime / duration) * totalWidth
            if x >= x1 && x <= x2 { return region }
        }
        return nil
    }

    private func dominantLabel(for mapping: ChannelMapping) -> String {
        let all = mapping.intensity + mapping.sharpness + mapping.transient
        return all.max(by: { $0.weight < $1.weight })?.channelLabel ?? L10n.editorDefaultRegionLabel
    }
}
