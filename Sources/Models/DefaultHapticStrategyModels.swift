import Foundation

public enum DefaultHapticProfile: String, CaseIterable, Sendable, Equatable {
    case musicTrailer
    case speechFirst
    case balanced
}

public enum DefaultHapticStrategyState: String, CaseIterable, Sendable, Equatable {
    case kickLead
    case vocalLead
    case balanced
}

public struct DefaultHapticStateSegment: Sendable, Equatable {
    public let state: DefaultHapticStrategyState
    public let start: TimeInterval
    public let end: TimeInterval

    public init(state: DefaultHapticStrategyState, start: TimeInterval, end: TimeInterval) {
        self.state = state
        self.start = max(0, start)
        self.end = max(self.start, end)
    }

    public var duration: TimeInterval {
        max(0, end - start)
    }
}

public struct DefaultHapticStrategyDiagnostics: Sendable, Equatable {
    public let kickLeadRatio: Float
    public let vocalLeadRatio: Float
    public let balancedRatio: Float
    public let lfeAvailable: Bool
    public let fallbackReasons: [String]

    public init(
        kickLeadRatio: Float,
        vocalLeadRatio: Float,
        balancedRatio: Float,
        lfeAvailable: Bool,
        fallbackReasons: [String]
    ) {
        self.kickLeadRatio = max(0, min(1, kickLeadRatio))
        self.vocalLeadRatio = max(0, min(1, vocalLeadRatio))
        self.balancedRatio = max(0, min(1, balancedRatio))
        self.lfeAvailable = lfeAvailable
        self.fallbackReasons = fallbackReasons
    }

    public var dominantState: DefaultHapticStrategyState {
        if kickLeadRatio >= vocalLeadRatio && kickLeadRatio >= balancedRatio {
            return .kickLead
        }
        if vocalLeadRatio >= balancedRatio {
            return .vocalLead
        }
        return .balanced
    }
}

public struct DefaultHapticStrategyResult: Sendable, Equatable {
    public let mapping: ChannelMapping
    public let recommendedTransientSensitivity: Float
    public let diagnostics: DefaultHapticStrategyDiagnostics
    public let segments: [DefaultHapticStateSegment]

    public init(
        mapping: ChannelMapping,
        recommendedTransientSensitivity: Float,
        diagnostics: DefaultHapticStrategyDiagnostics,
        segments: [DefaultHapticStateSegment]
    ) {
        self.mapping = mapping
        self.recommendedTransientSensitivity = max(0, min(1, recommendedTransientSensitivity))
        self.diagnostics = diagnostics
        self.segments = segments.sorted { $0.start < $1.start }
    }
}

