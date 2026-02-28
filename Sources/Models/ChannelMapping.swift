import Foundation

public enum HapticFeature: Sendable {
    case intensity
    case sharpness
    case transient
}

public struct ChannelWeight: Sendable, Equatable {
    public let channelLabel: String
    public let weight: Float

    public init(channelLabel: String, weight: Float) {
        self.channelLabel = channelLabel
        self.weight = max(0, weight)
    }
}

public struct ChannelMapping: Sendable, Equatable {
    public var intensity: [ChannelWeight]
    public var sharpness: [ChannelWeight]
    public var transient: [ChannelWeight]

    public init(intensity: [ChannelWeight], sharpness: [ChannelWeight], transient: [ChannelWeight]) {
        self.intensity = intensity
        self.sharpness = sharpness
        self.transient = transient
    }

    public func weights(for feature: HapticFeature) -> [ChannelWeight] {
        switch feature {
        case .intensity:
            return intensity
        case .sharpness:
            return sharpness
        case .transient:
            return transient
        }
    }

    public func normalizedWeights(for feature: HapticFeature, availableLabels: [String]) -> [ChannelWeight] {
        let raw = weights(for: feature).filter { item in
            availableLabels.contains(item.channelLabel) && item.weight > 0
        }

        let base: [ChannelWeight]
        if raw.isEmpty {
            base = fallbackWeights(for: feature, labels: availableLabels)
        } else {
            base = raw
        }

        let sum = base.reduce(Float(0)) { $0 + $1.weight }
        guard sum > 0 else {
            return []
        }

        return base.map { ChannelWeight(channelLabel: $0.channelLabel, weight: $0.weight / sum) }
    }

    private func fallbackWeights(for feature: HapticFeature, labels: [String]) -> [ChannelWeight] {
        if labels.isEmpty {
            return []
        }

        let lfeCandidates = ["LFE", "LFE1", "LFE2"].filter(labels.contains)
        let l = labels.contains("L") ? "L" : labels.first!
        let r = labels.contains("R") ? "R" : labels.dropFirst().first ?? l
        let c = labels.contains("C") ? "C" : l

        switch feature {
        case .intensity:
            if let lfe = lfeCandidates.first {
                return [
                    ChannelWeight(channelLabel: lfe, weight: 1.0),
                    ChannelWeight(channelLabel: l, weight: 0.5),
                    ChannelWeight(channelLabel: r, weight: 0.5)
                ]
            }
            return [
                ChannelWeight(channelLabel: l, weight: 1.0),
                ChannelWeight(channelLabel: r, weight: 1.0)
            ]
        case .sharpness:
            return [
                ChannelWeight(channelLabel: l, weight: 0.7),
                ChannelWeight(channelLabel: r, weight: 0.7),
                ChannelWeight(channelLabel: c, weight: 0.3)
            ]
        case .transient:
            return [
                ChannelWeight(channelLabel: l, weight: 0.8),
                ChannelWeight(channelLabel: r, weight: 0.8),
                ChannelWeight(channelLabel: c, weight: 0.5)
            ]
        }
    }

    public static func defaults(for layout: ChannelLayout) -> ChannelMapping {
        let labels = layout.labels
        switch layout.type {
        case .binaural2:
            return ChannelMapping(
                intensity: [ChannelWeight(channelLabel: "L", weight: 1), ChannelWeight(channelLabel: "R", weight: 1)],
                sharpness: [ChannelWeight(channelLabel: "L", weight: 1), ChannelWeight(channelLabel: "R", weight: 1)],
                transient: [ChannelWeight(channelLabel: "L", weight: 1), ChannelWeight(channelLabel: "R", weight: 1)]
            )
        default:
            return ChannelMapping(intensity: [], sharpness: [], transient: [])
                .withFallbackResolved(using: labels)
        }
    }

    public func withFallbackResolved(using labels: [String]) -> ChannelMapping {
        ChannelMapping(
            intensity: normalizedWeights(for: .intensity, availableLabels: labels),
            sharpness: normalizedWeights(for: .sharpness, availableLabels: labels),
            transient: normalizedWeights(for: .transient, availableLabels: labels)
        )
    }
}
