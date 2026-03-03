import Foundation

public enum TrackHapticStyle: String, CaseIterable, Sendable, Equatable {
    case continuous
    case transientBurst
    case pulseTexture
}

public enum FrequencyBandKind: String, CaseIterable, Sendable, Equatable {
    case sub
    case low
    case mid
    case high
    case custom
}

public struct FrequencyBand: Sendable, Equatable {
    public var kind: FrequencyBandKind
    public var customMinHz: Float
    public var customMaxHz: Float

    public init(kind: FrequencyBandKind, customMinHz: Float = 20, customMaxHz: Float = 200) {
        self.kind = kind
        self.customMinHz = customMinHz
        self.customMaxHz = customMaxHz
    }

    public func range(sampleRate: Double) -> ClosedRange<Double> {
        let nyquist = max(1, sampleRate * 0.5)
        switch kind {
        case .sub:
            return 20...60
        case .low:
            return 60...180
        case .mid:
            return 180...1200
        case .high:
            return 1200...min(6000, nyquist)
        case .custom:
            let lower = Double(min(customMinHz, customMaxHz))
            let upper = Double(max(customMinHz, customMaxHz))
            return max(0, lower)...max(0, min(upper, nyquist))
        }
    }

    public static let `sub` = FrequencyBand(kind: .sub)
    public static let low = FrequencyBand(kind: .low)
    public static let mid = FrequencyBand(kind: .mid)
    public static let high = FrequencyBand(kind: .high)
}

public enum ChannelGroupKind: String, CaseIterable, Sendable, Equatable {
    case front
    case rear
    case top
    case lfe
    case all
    case custom
}

public struct ChannelGroup: Sendable, Equatable {
    public var kind: ChannelGroupKind
    public var customLabels: [String]

    public init(kind: ChannelGroupKind, customLabels: [String] = []) {
        self.kind = kind
        self.customLabels = customLabels
    }

    public func resolveLabels(from available: [String]) -> [String] {
        let normalized = Set(available)
        let picked: [String]

        switch kind {
        case .front:
            let candidates = ["L", "R", "C", "Lc", "Rc", "Lw", "Rw"]
            picked = candidates.filter { normalized.contains($0) }
        case .rear:
            let candidates = ["Ls", "Rs", "Rls", "Rrs", "Sl", "Sr", "Bl", "Br"]
            picked = candidates.filter { normalized.contains($0) }
        case .top:
            picked = available.filter {
                $0.hasPrefix("V") || $0.hasPrefix("T") || $0.localizedCaseInsensitiveContains("top")
            }
        case .lfe:
            picked = available.filter { $0.localizedCaseInsensitiveContains("lfe") }
        case .all:
            picked = available
        case .custom:
            let custom = Set(customLabels)
            picked = available.filter { custom.contains($0) }
        }

        if picked.isEmpty {
            return Array(available.prefix(2))
        }
        return picked
    }

    public static let front = ChannelGroup(kind: .front)
    public static let rear = ChannelGroup(kind: .rear)
    public static let top = ChannelGroup(kind: .top)
    public static let lfe = ChannelGroup(kind: .lfe)
    public static let all = ChannelGroup(kind: .all)
}

public struct TrackSource: Sendable, Equatable {
    public var channelGroup: ChannelGroup
    public var frequencyBand: FrequencyBand

    public init(channelGroup: ChannelGroup, frequencyBand: FrequencyBand) {
        self.channelGroup = channelGroup
        self.frequencyBand = frequencyBand
    }
}

public struct TrackKeyframe: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var time: TimeInterval
    public var value: Float

    public init(id: UUID = UUID(), time: TimeInterval, value: Float) {
        self.id = id
        self.time = max(0, time)
        self.value = max(0, min(1, value))
    }
}

public struct ClipTransientRule: Sendable, Equatable {
    public var threshold: Float
    public var cooldown: TimeInterval
    public var gain: Float

    public init(threshold: Float = 0.5, cooldown: TimeInterval = 0.03, gain: Float = 1.0) {
        self.threshold = max(0, min(1, threshold))
        self.cooldown = max(0, cooldown)
        self.gain = max(0, gain)
    }
}

public struct TimelineClip: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var start: TimeInterval
    public var duration: TimeInterval
    public var intensityKeyframes: [TrackKeyframe]
    public var sharpnessKeyframes: [TrackKeyframe]
    public var transientRule: ClipTransientRule
    public var pulseRate: Float
    public var pulseDepth: Float

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        duration: TimeInterval,
        intensityKeyframes: [TrackKeyframe] = [TrackKeyframe(time: 0, value: 0.7), TrackKeyframe(time: 1, value: 0.7)],
        sharpnessKeyframes: [TrackKeyframe] = [TrackKeyframe(time: 0, value: 0.5), TrackKeyframe(time: 1, value: 0.5)],
        transientRule: ClipTransientRule = .init(),
        pulseRate: Float = 6,
        pulseDepth: Float = 0.4
    ) {
        self.id = id
        self.start = max(0, start)
        self.duration = max(0.05, duration)
        self.intensityKeyframes = TimelineClip.normalized(intensityKeyframes)
        self.sharpnessKeyframes = TimelineClip.normalized(sharpnessKeyframes)
        self.transientRule = transientRule
        self.pulseRate = max(0.5, min(20, pulseRate))
        self.pulseDepth = max(0, min(1, pulseDepth))
    }

    public var end: TimeInterval { start + duration }

    private static func normalized(_ keyframes: [TrackKeyframe]) -> [TrackKeyframe] {
        if keyframes.isEmpty {
            return [TrackKeyframe(time: 0, value: 0.5), TrackKeyframe(time: 1, value: 0.5)]
        }
        return keyframes.sorted { $0.time < $1.time }
    }
}

public struct HapticTrack: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var isMuted: Bool
    public var isSolo: Bool
    public var style: TrackHapticStyle
    public var source: TrackSource
    public var mixWeight: Float
    public var maxOutput: Float
    public var clips: [TimelineClip]

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        isMuted: Bool = false,
        isSolo: Bool = false,
        style: TrackHapticStyle,
        source: TrackSource,
        mixWeight: Float = 1,
        maxOutput: Float = 1,
        clips: [TimelineClip]
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.style = style
        self.source = source
        self.mixWeight = max(0, mixWeight)
        self.maxOutput = max(0, min(1, maxOutput))
        self.clips = clips.sorted { $0.start < $1.start }
    }
}

public enum TimelineTemplate: String, CaseIterable, Sendable, Equatable {
    case trailer
    case music
    case action
}

public struct HapticTimelineDocument: Sendable, Equatable {
    public static let maxTracks = 6

    public let id: UUID
    public var duration: TimeInterval
    public var tracks: [HapticTrack]
    public var template: TimelineTemplate

    public init(id: UUID = UUID(), duration: TimeInterval, tracks: [HapticTrack], template: TimelineTemplate = .trailer) {
        self.id = id
        self.duration = max(0.1, duration)
        self.tracks = Array(tracks.prefix(Self.maxTracks))
        self.template = template
    }

    public static func `default`(for layout: ChannelLayout, duration: TimeInterval, template: TimelineTemplate = .trailer) -> HapticTimelineDocument {
        let baseClip = TimelineClip(start: 0, duration: max(1, duration))

        let rumble = HapticTrack(
            name: "Rumble",
            style: .continuous,
            source: TrackSource(channelGroup: .lfe, frequencyBand: .sub),
            mixWeight: template == .music ? 0.8 : 1.0,
            maxOutput: 1.0,
            clips: [baseClip]
        )

        let texture = HapticTrack(
            name: "Texture",
            style: .pulseTexture,
            source: TrackSource(channelGroup: .front, frequencyBand: template == .action ? .high : .mid),
            mixWeight: 0.8,
            maxOutput: 0.85,
            clips: [TimelineClip(start: 0, duration: max(1, duration), pulseRate: template == .music ? 8 : 6, pulseDepth: 0.35)]
        )

        let impact = HapticTrack(
            name: "Impact",
            style: .transientBurst,
            source: TrackSource(channelGroup: layout.channelCount > 2 ? .front : .all, frequencyBand: .low),
            mixWeight: 1.0,
            maxOutput: template == .action ? 1.0 : 0.9,
            clips: [TimelineClip(start: 0, duration: max(1, duration), transientRule: ClipTransientRule(threshold: template == .music ? 0.65 : 0.5, cooldown: 0.03, gain: 1.0))]
        )

        return HapticTimelineDocument(duration: duration, tracks: [rumble, texture, impact], template: template)
    }
}
