import SwiftUI

/// 时间标尺：显示秒刻度线和时间标签
struct TimeRulerView: View {
    let duration: TimeInterval
    let totalWidth: CGFloat

    private let rulerHeight: CGFloat = 30
    private let tickInterval: TimeInterval = 1.0  // 每秒一个主刻度

    var body: some View {
        Canvas { context, size in
            drawBackground(context: &context, size: size)
            drawTicks(context: &context, size: size)
        }
        .frame(width: totalWidth, height: rulerHeight)
    }

    // MARK: - 绘制

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func drawTicks(context: inout GraphicsContext, size: CGSize) {
        guard duration > 0 else { return }

        // 每像素对应的秒数
        let secondsPerPixel = duration / Double(size.width)
        // 根据缩放级别动态调整刻度间距（最少 40px 一个刻度）
        let minPixelsPerTick: Double = 40
        let rawInterval = minPixelsPerTick * secondsPerPixel
        let interval = niceInterval(rawInterval)

        var time = 0.0
        while time <= duration + interval * 0.5 {
            let x = CGFloat(time / duration) * size.width
            let isMajor = (time.truncatingRemainder(dividingBy: interval) < 0.001)

            // 刻度线
            let tickHeight: CGFloat = isMajor ? 12 : 6
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: size.height))
            tickPath.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
            context.stroke(tickPath, with: .color(.secondary), lineWidth: 1)

            // 时间标签（主刻度才显示）
            if isMajor {
                let label = formatTime(time)
                var textRect = CGRect(x: x + 3, y: 2, width: 60, height: 16)
                if x + 65 > size.width {
                    textRect.origin.x = x - 65
                }
                context.draw(
                    Text(label)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary),
                    in: textRect
                )
            }

            time += interval
        }
    }

    // MARK: - 辅助

    private func niceInterval(_ raw: Double) -> Double {
        let candidates: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60]
        return candidates.first(where: { $0 >= raw }) ?? 60
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            if seconds.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0fs", seconds)
            } else {
                return String(format: "%.1fs", seconds)
            }
        }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
