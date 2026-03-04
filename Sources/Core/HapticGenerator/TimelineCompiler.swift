import Foundation

public final class TimelineCompiler: @unchecked Sendable {
    public init() {}

    public func compile(
        document: HapticTimelineDocument,
        analysis: MultiChannelAnalysisResult,
        settings: GeneratorSettings
    ) throws -> HapticPatternDescriptor {
        try compileCore(
            document: document,
            analysis: analysis,
            settings: settings,
            window: nil,
            outputTimeOffset: 0
        )
    }

    public func compileWindow(
        document: HapticTimelineDocument,
        analysis: MultiChannelAnalysisResult,
        settings: GeneratorSettings,
        timeRange: ClosedRange<TimeInterval>
    ) throws -> HapticPatternDescriptor {
        let lower = max(0, timeRange.lowerBound)
        let upper = min(analysis.duration, max(lower, timeRange.upperBound))
        let window = lower...upper

        return try compileCore(
            document: document,
            analysis: analysis,
            settings: settings,
            window: window,
            outputTimeOffset: lower
        )
    }

    private func compileCore(
        document: HapticTimelineDocument,
        analysis: MultiChannelAnalysisResult,
        settings: GeneratorSettings,
        window: ClosedRange<TimeInterval>?,
        outputTimeOffset: TimeInterval
    ) throws -> HapticPatternDescriptor {
        guard !analysis.channels.isEmpty else {
            throw AudioHapticError.generationFailed(L10n.Key.errorDetailEmptyAnalysisResult)
        }

        let frameCount = analysis.channels.map { $0.frames.count }.min() ?? 0
        guard frameCount > 0 else {
            throw AudioHapticError.generationFailed(L10n.Key.errorDetailNoFramesAvailable)
        }

        let times = analysis.channels[0].frames.prefix(frameCount).map(\.time)
        let labels = analysis.channels.map(\.label)
        let frameIndices = frameIndices(in: times, window: window)
        let descriptorDuration = window.map { max(0.05, $0.upperBound - $0.lowerBound) } ?? analysis.duration

        let activeTracks = resolvedActiveTracks(document.tracks)
        if activeTracks.isEmpty {
            return HapticPatternDescriptor(
                duration: descriptorDuration,
                continuousEvent: ContinuousEventDescriptor(duration: descriptorDuration),
                intensityCurvePoints: [CurvePoint(time: 0, value: 0)],
                sharpnessCurvePoints: [CurvePoint(time: 0, value: 0.5)],
                transientEvents: []
            )
        }

        var cache: [SourceCacheKey: SourceMetrics] = [:]
        var intensityPoints: [CurvePoint] = []
        var sharpnessPoints: [CurvePoint] = []
        var transientEvents: [TransientPoint] = []
        var lastTransientByClip: [UUID: TimeInterval] = [:]

        intensityPoints.reserveCapacity(max(frameIndices.count, 1))
        sharpnessPoints.reserveCapacity(max(frameIndices.count, 1))

        for frameIndex in frameIndices {
            let absoluteTime = times[frameIndex]
            let outputTime = max(0, absoluteTime - outputTimeOffset)

            var weightedIntensity: Float = 0
            var weightedSharpness: Float = 0
            var weightSum: Float = 0

            for track in activeTracks {
                let clips = track.clips.filter { absoluteTime >= $0.start && absoluteTime <= $0.end }
                guard !clips.isEmpty else { continue }

                let key = SourceCacheKey(track.source)
                let metrics: SourceMetrics
                if let existing = cache[key] {
                    metrics = existing
                } else {
                    let computed = computeMetrics(source: track.source, analysis: analysis, labels: labels, frameCount: frameCount)
                    cache[key] = computed
                    metrics = computed
                }

                let srcIntensity = metrics.intensity[frameIndex]
                let srcSharpness = metrics.sharpness[frameIndex]
                let srcTransient = metrics.transient[frameIndex]

                for clip in clips {
                    let localTime = absoluteTime - clip.start
                    let localNorm = clip.duration > 0 ? localTime / clip.duration : 0
                    let intensityEnvelope = evaluate(keyframes: clip.intensityKeyframes, atNormalizedTime: localNorm)
                    let sharpnessEnvelope = evaluate(keyframes: clip.sharpnessKeyframes, atNormalizedTime: localNorm)

                    let mix = track.mixWeight
                    let output = track.maxOutput

                    switch track.style {
                    case .continuous:
                        weightedIntensity += srcIntensity * intensityEnvelope * output * mix
                        weightedSharpness += srcSharpness * sharpnessEnvelope * output * mix
                        weightSum += mix

                    case .pulseTexture:
                        let pulse = (sinf(2 * .pi * clip.pulseRate * Float(localTime)) + 1) * 0.5
                        let pulseGain = (1 - clip.pulseDepth) + clip.pulseDepth * pulse
                        weightedIntensity += srcIntensity * intensityEnvelope * pulseGain * output * mix
                        weightedSharpness += srcSharpness * sharpnessEnvelope * output * mix
                        weightSum += mix

                    case .transientBurst:
                        weightedIntensity += srcIntensity * 0.15 * intensityEnvelope * output * mix
                        weightedSharpness += srcSharpness * 0.15 * sharpnessEnvelope * output * mix
                        weightSum += mix

                        let threshold = max(clip.transientRule.threshold, settings.transientSensitivity)
                        let boostedTransient = srcTransient * clip.transientRule.gain
                        let lastTime = lastTransientByClip[clip.id] ?? -.greatestFiniteMagnitude

                        if boostedTransient >= threshold && (absoluteTime - lastTime) >= clip.transientRule.cooldown {
                            transientEvents.append(
                                TransientPoint(
                                    time: outputTime,
                                    intensity: clamp01(srcIntensity * intensityEnvelope * clip.transientRule.gain * settings.intensityScale),
                                    sharpness: clamp01(srcSharpness * sharpnessEnvelope + settings.sharpnessBias)
                                )
                            )
                            lastTransientByClip[clip.id] = absoluteTime
                        }
                    }
                }
            }

            let mixedIntensity = weightSum > 0 ? weightedIntensity / weightSum : 0
            let mixedSharpness = weightSum > 0 ? weightedSharpness / weightSum : 0.5

            intensityPoints.append(CurvePoint(time: outputTime, value: clamp01(mixedIntensity * settings.intensityScale)))
            sharpnessPoints.append(CurvePoint(time: outputTime, value: clamp01(mixedSharpness + settings.sharpnessBias)))
        }

        if intensityPoints.isEmpty {
            intensityPoints = [CurvePoint(time: 0, value: 0)]
        }
        if sharpnessPoints.isEmpty {
            sharpnessPoints = [CurvePoint(time: 0, value: 0.5)]
        }

        return HapticPatternDescriptor(
            duration: descriptorDuration,
            continuousEvent: ContinuousEventDescriptor(duration: descriptorDuration),
            intensityCurvePoints: finalizeCurve(points: intensityPoints, density: settings.eventDensity),
            sharpnessCurvePoints: finalizeCurve(points: sharpnessPoints, density: settings.eventDensity),
            transientEvents: transientEvents
        )
    }

    private func frameIndices(in times: [TimeInterval], window: ClosedRange<TimeInterval>?) -> [Int] {
        guard let window else {
            return Array(times.indices)
        }
        guard !times.isEmpty else { return [] }

        let lower = window.lowerBound
        let upper = window.upperBound

        var result: [Int] = []
        result.reserveCapacity(times.count / 8)

        for index in times.indices {
            let time = times[index]
            if time < lower {
                continue
            }
            if time > upper {
                break
            }
            result.append(index)
        }
        return result
    }

    private func resolvedActiveTracks(_ tracks: [HapticTrack]) -> [HapticTrack] {
        let enabled = tracks.filter { $0.isEnabled && !$0.isMuted }
        let soloed = enabled.filter(\.isSolo)
        return soloed.isEmpty ? enabled : soloed
    }

    private func computeMetrics(
        source: TrackSource,
        analysis: MultiChannelAnalysisResult,
        labels: [String],
        frameCount: Int
    ) -> SourceMetrics {
        let resolvedLabels = source.channelGroup.resolveLabels(from: labels)
        let labelSet = Set(resolvedLabels)
        let indices = labels.enumerated().compactMap { labelSet.contains($0.element) ? $0.offset : nil }
        let resolvedIndices = indices.isEmpty ? Array(analysis.channels.indices) : indices

        let bandRange = source.frequencyBand.range(sampleRate: analysis.sampleRate)
        let nyquist = max(1, analysis.sampleRate * 0.5)
        let bandCenterNorm = Float(((bandRange.lowerBound + bandRange.upperBound) * 0.5) / nyquist)
        let bandWidthNorm = max(Float((bandRange.upperBound - bandRange.lowerBound) / nyquist), 0.05)

        var intensity = Array(repeating: Float(0), count: frameCount)
        var sharpness = Array(repeating: Float(0.5), count: frameCount)
        var transient = Array(repeating: Float(0), count: frameCount)

        for frameIndex in 0..<frameCount {
            var rmsSum: Float = 0
            var centroidSum: Float = 0
            var transientMax: Float = 0

            for channelIndex in resolvedIndices {
                let frame = analysis.channels[channelIndex].frames[frameIndex]
                rmsSum += frame.rms
                centroidSum += frame.spectralCentroidNorm
                transientMax = max(transientMax, frame.transientStrength)
            }

            let divisor = Float(max(1, resolvedIndices.count))
            let rmsAvg = rmsSum / divisor
            let centroidAvg = centroidSum / divisor

            let bandWeight = gaussianWeight(x: centroidAvg, center: bandCenterNorm, width: bandWidthNorm)
            intensity[frameIndex] = clamp01(rmsAvg * bandWeight)
            sharpness[frameIndex] = clamp01(centroidAvg)
            transient[frameIndex] = clamp01(transientMax * bandWeight)
        }

        return SourceMetrics(intensity: intensity, sharpness: sharpness, transient: transient)
    }

    private func evaluate(keyframes: [TrackKeyframe], atNormalizedTime normalizedTime: TimeInterval) -> Float {
        let t = Float(max(0, min(1, normalizedTime)))
        guard !keyframes.isEmpty else { return 0.5 }
        let sorted = keyframes.sorted { $0.time < $1.time }

        if t <= Float(sorted[0].time) {
            return sorted[0].value
        }
        if let last = sorted.last, t >= Float(last.time) {
            return last.value
        }

        for index in 0..<(sorted.count - 1) {
            let lhs = sorted[index]
            let rhs = sorted[index + 1]
            let lhsT = Float(lhs.time)
            let rhsT = Float(rhs.time)
            guard t >= lhsT && t <= rhsT else { continue }

            let segment = max(0.0001, rhsT - lhsT)
            let progress = (t - lhsT) / segment
            return clamp01(lhs.value + (rhs.value - lhs.value) * progress)
        }

        return sorted.last?.value ?? 0.5
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

    private func enforcePointLimit(_ points: [CurvePoint], limit: Int = HapticExporter.maxControlPointCount) -> [CurvePoint] {
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

    private func gaussianWeight(x: Float, center: Float, width: Float) -> Float {
        let sigma = max(width * 0.5, 0.05)
        let exponent = -pow((x - center) / sigma, 2) * 0.5
        return max(0.1, exp(exponent))
    }

    private func clamp01(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}

private struct SourceCacheKey: Hashable {
    let channelKind: ChannelGroupKind
    let channelLabels: String
    let bandKind: FrequencyBandKind
    let bandMin: Float
    let bandMax: Float

    init(_ source: TrackSource) {
        self.channelKind = source.channelGroup.kind
        self.channelLabels = source.channelGroup.customLabels.sorted().joined(separator: ",")
        self.bandKind = source.frequencyBand.kind
        self.bandMin = source.frequencyBand.customMinHz
        self.bandMax = source.frequencyBand.customMaxHz
    }
}

private struct SourceMetrics {
    let intensity: [Float]
    let sharpness: [Float]
    let transient: [Float]
}
