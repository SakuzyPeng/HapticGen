import Foundation

public actor AnalysisCache {
    private let analysis: MultiChannelAnalysisResult
    private var cache: [CacheKey: CachedSeries] = [:]

    public init(analysis: MultiChannelAnalysisResult) {
        self.analysis = analysis
    }

    public func series(for source: TrackSource) -> CachedSeries {
        let key = CacheKey(source)
        if let cached = cache[key] {
            return cached
        }

        let generated = build(source: source)
        cache[key] = generated
        return generated
    }

    private func build(source: TrackSource) -> CachedSeries {
        let labels = analysis.channels.map(\.label)
        let selectedLabels = source.channelGroup.resolveLabels(from: labels)
        let selectedSet = Set(selectedLabels)
        let indices = labels.enumerated().compactMap { selectedSet.contains($0.element) ? $0.offset : nil }
        let resolvedIndices = indices.isEmpty ? Array(analysis.channels.indices) : indices

        let frameCount = analysis.channels.map { $0.frames.count }.min() ?? 0
        guard frameCount > 0 else {
            return CachedSeries(times: [], intensity: [], sharpness: [], transient: [])
        }

        let range = source.frequencyBand.range(sampleRate: analysis.sampleRate)
        let nyquist = max(1, analysis.sampleRate * 0.5)
        let center = Float(((range.lowerBound + range.upperBound) * 0.5) / nyquist)
        let width = max(Float((range.upperBound - range.lowerBound) / nyquist), 0.05)

        var times: [TimeInterval] = []
        var intensity: [Float] = []
        var sharpness: [Float] = []
        var transient: [Float] = []

        times.reserveCapacity(frameCount)
        intensity.reserveCapacity(frameCount)
        sharpness.reserveCapacity(frameCount)
        transient.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let time = analysis.channels[0].frames[frameIndex].time
            var rmsSum: Float = 0
            var centroidSum: Float = 0
            var transientMax: Float = 0

            for idx in resolvedIndices {
                let frame = analysis.channels[idx].frames[frameIndex]
                rmsSum += frame.rms
                centroidSum += frame.spectralCentroidNorm
                transientMax = max(transientMax, frame.transientStrength)
            }

            let divisor = Float(max(1, resolvedIndices.count))
            let rms = rmsSum / divisor
            let centroid = centroidSum / divisor
            let bandWeight = gaussianWeight(x: centroid, center: center, width: width)

            times.append(time)
            intensity.append(clamp01(rms * bandWeight))
            sharpness.append(clamp01(centroid))
            transient.append(clamp01(transientMax * bandWeight))
        }

        return CachedSeries(times: times, intensity: intensity, sharpness: sharpness, transient: transient)
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

public struct CachedSeries: Sendable {
    public let times: [TimeInterval]
    public let intensity: [Float]
    public let sharpness: [Float]
    public let transient: [Float]
}

private struct CacheKey: Hashable {
    let channelKind: ChannelGroupKind
    let customLabels: String
    let bandKind: FrequencyBandKind
    let bandMin: Float
    let bandMax: Float

    init(_ source: TrackSource) {
        self.channelKind = source.channelGroup.kind
        self.customLabels = source.channelGroup.customLabels.sorted().joined(separator: ",")
        self.bandKind = source.frequencyBand.kind
        self.bandMin = source.frequencyBand.customMinHz
        self.bandMax = source.frequencyBand.customMaxHz
    }
}
