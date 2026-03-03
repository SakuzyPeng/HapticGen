import Foundation

public final class HapticGenerator: @unchecked Sendable {
    public init() {}

    public func generate(
        from analysis: MultiChannelAnalysisResult,
        mapping: ChannelMapping,
        settings: GeneratorSettings
    ) throws -> HapticPatternDescriptor {
        guard !analysis.channels.isEmpty else {
            throw AudioHapticError.generationFailed(L10n.Key.errorDetailEmptyAnalysisResult)
        }

        let labels = analysis.channels.map(\.label)
        let resolvedMapping = mapping.withFallbackResolved(using: labels)

        let indexByLabel = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        let frameCount = analysis.channels.map { $0.frames.count }.min() ?? 0

        guard frameCount > 0 else {
            throw AudioHapticError.generationFailed(L10n.Key.errorDetailNoFramesAvailable)
        }

        let intensityWeights = resolvedMapping.normalizedWeights(for: .intensity, availableLabels: labels)
        let sharpnessWeights = resolvedMapping.normalizedWeights(for: .sharpness, availableLabels: labels)
        let transientWeights = resolvedMapping.normalizedWeights(for: .transient, availableLabels: labels)

        var intensityPoints: [CurvePoint] = []
        var sharpnessPoints: [CurvePoint] = []
        var transientEvents: [TransientPoint] = []

        var lastTransientTime: TimeInterval = -.greatestFiniteMagnitude
        var recentTransientTimes: [TimeInterval] = []

        for frameIndex in 0..<frameCount {
            let time = analysis.channels[0].frames[frameIndex].time

            let rawIntensity = weightedAverage(
                framesAt: frameIndex,
                channels: analysis.channels,
                weights: intensityWeights,
                indexByLabel: indexByLabel,
                keyPath: \.rms
            )
            let rawSharpness = weightedAverage(
                framesAt: frameIndex,
                channels: analysis.channels,
                weights: sharpnessWeights,
                indexByLabel: indexByLabel,
                keyPath: \.spectralCentroidNorm
            )
            let rawTransient = weightedMax(
                framesAt: frameIndex,
                channels: analysis.channels,
                weights: transientWeights,
                indexByLabel: indexByLabel,
                keyPath: \.transientStrength
            )

            let intensity = clamp01(rawIntensity * settings.intensityScale)
            let sharpness = clamp01(rawSharpness + settings.sharpnessBias)

            intensityPoints.append(CurvePoint(time: time, value: intensity))
            sharpnessPoints.append(CurvePoint(time: time, value: sharpness))

            let hasMinGap = (time - lastTransientTime) >= settings.transientMinInterval
            if rawTransient >= settings.transientSensitivity && hasMinGap {
                recentTransientTimes.removeAll { time - $0 > 1.0 }
                if recentTransientTimes.count < settings.transientMaxPerSecond {
                    transientEvents.append(
                        TransientPoint(
                            time: time,
                            intensity: max(intensity, clamp01(rawTransient)),
                            sharpness: sharpness
                        )
                    )
                    recentTransientTimes.append(time)
                    lastTransientTime = time
                }
            }
        }

        let processedIntensity = finalizeCurve(points: intensityPoints, density: settings.eventDensity)
        let processedSharpness = finalizeCurve(points: sharpnessPoints, density: settings.eventDensity)

        return HapticPatternDescriptor(
            duration: analysis.duration,
            continuousEvent: ContinuousEventDescriptor(duration: analysis.duration),
            intensityCurvePoints: processedIntensity,
            sharpnessCurvePoints: processedSharpness,
            transientEvents: transientEvents
        )
    }

    private func weightedAverage(
        framesAt frameIndex: Int,
        channels: [ChannelAnalysisResult],
        weights: [ChannelWeight],
        indexByLabel: [String: Int],
        keyPath: KeyPath<ChannelFeatureFrame, Float>
    ) -> Float {
        guard !weights.isEmpty else { return 0 }

        var total: Float = 0
        var totalWeight: Float = 0

        for item in weights {
            guard let channelIndex = indexByLabel[item.channelLabel],
                  frameIndex < channels[channelIndex].frames.count
            else {
                continue
            }
            let value = channels[channelIndex].frames[frameIndex][keyPath: keyPath]
            total += value * item.weight
            totalWeight += item.weight
        }

        guard totalWeight > 0 else {
            return 0
        }
        return total / totalWeight
    }

    private func weightedMax(
        framesAt frameIndex: Int,
        channels: [ChannelAnalysisResult],
        weights: [ChannelWeight],
        indexByLabel: [String: Int],
        keyPath: KeyPath<ChannelFeatureFrame, Float>
    ) -> Float {
        guard !weights.isEmpty else { return 0 }

        var output: Float = 0

        for item in weights {
            guard let channelIndex = indexByLabel[item.channelLabel],
                  frameIndex < channels[channelIndex].frames.count
            else {
                continue
            }
            let value = channels[channelIndex].frames[frameIndex][keyPath: keyPath] * item.weight
            output = max(output, value)
        }

        return output
    }

    private func finalizeCurve(points: [CurvePoint], density: Float) -> [CurvePoint] {
        guard points.count > 2 else {
            return enforcePointLimit(points)
        }

        let processed: [CurvePoint]
        if density < 1.0 {
            let epsilon = Double((1.0 - density) * 0.06)
            processed = rdpSimplify(points: points, epsilon: epsilon)
        } else if density > 1.0 {
            let factor = max(1, Int(density.rounded(.down)))
            processed = interpolate(points: points, factor: factor)
        } else {
            processed = points
        }

        return enforcePointLimit(processed)
    }

    private func enforcePointLimit(_ points: [CurvePoint], limit: Int = 16384) -> [CurvePoint] {
        guard points.count > limit, limit > 1 else {
            return points
        }

        let strideValue = Double(points.count - 1) / Double(limit - 1)
        var output: [CurvePoint] = []
        output.reserveCapacity(limit)

        for idx in 0..<limit {
            let sourceIndex = Int((Double(idx) * strideValue).rounded())
            output.append(points[min(sourceIndex, points.count - 1)])
        }
        return output
    }

    private func interpolate(points: [CurvePoint], factor: Int) -> [CurvePoint] {
        guard factor > 1 else {
            return points
        }

        var output: [CurvePoint] = []
        output.reserveCapacity(points.count * factor)

        for index in 0..<(points.count - 1) {
            let left = points[index]
            let right = points[index + 1]
            output.append(left)

            for step in 1..<factor {
                let t = Float(step) / Float(factor)
                let time = left.time + (right.time - left.time) * Double(t)
                let value = left.value + ((right.value - left.value) * t)
                output.append(CurvePoint(time: time, value: value))
            }
        }

        if let last = points.last {
            output.append(last)
        }

        return output
    }

    private func rdpSimplify(points: [CurvePoint], epsilon: Double) -> [CurvePoint] {
        guard points.count > 2 else { return points }

        let first = points[0]
        let last = points[points.count - 1]

        var maxDistance: Double = 0
        var splitIndex: Int = 0

        for index in 1..<(points.count - 1) {
            let distance = perpendicularDistance(point: points[index], lineStart: first, lineEnd: last)
            if distance > maxDistance {
                maxDistance = distance
                splitIndex = index
            }
        }

        if maxDistance > epsilon {
            let left = rdpSimplify(points: Array(points[0...splitIndex]), epsilon: epsilon)
            let right = rdpSimplify(points: Array(points[splitIndex...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }

        return [first, last]
    }

    private func perpendicularDistance(point: CurvePoint, lineStart: CurvePoint, lineEnd: CurvePoint) -> Double {
        let x0 = point.time
        let y0 = Double(point.value)
        let x1 = lineStart.time
        let y1 = Double(lineStart.value)
        let x2 = lineEnd.time
        let y2 = Double(lineEnd.value)

        let denominator = hypot(x2 - x1, y2 - y1)
        guard denominator > 0 else {
            return hypot(x0 - x1, y0 - y1)
        }

        let numerator = abs((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1)
        return numerator / denominator
    }

    private func clamp01(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}
