import Foundation

public final class DefaultHapticStrategyResolver: @unchecked Sendable {
    private static let windowDuration: TimeInterval = 0.2
    private static let windowHop: TimeInterval = 0.1
    private static let minHoldDuration: TimeInterval = 1.5
    private static let switchDelta: Float = 0.15

    public init() {}

    public func resolve(
        analysis: MultiChannelAnalysisResult,
        layout: ChannelLayout? = nil,
        profile: DefaultHapticProfile = .musicTrailer
    ) -> DefaultHapticStrategyResult {
        let resolvedLayout = layout ?? analysis.layout
        let labels = analysis.channels.map(\.label)

        guard !analysis.channels.isEmpty,
              let frameCount = analysis.channels.map(\.frames.count).min(),
              frameCount > 0
        else {
            let fallbackMapping = ChannelMapping.defaults(for: resolvedLayout)
            let diagnostics = DefaultHapticStrategyDiagnostics(
                kickLeadRatio: 0,
                vocalLeadRatio: 0,
                balancedRatio: 1,
                lfeAvailable: false,
                fallbackReasons: ["empty-analysis"]
            )
            return DefaultHapticStrategyResult(
                mapping: fallbackMapping,
                recommendedTransientSensitivity: defaultTransientSensitivity(for: .balanced),
                diagnostics: diagnostics,
                segments: [DefaultHapticStateSegment(state: .balanced, start: 0, end: max(0.1, analysis.duration))]
            )
        }

        let channelProfiles = buildChannelProfiles(analysis: analysis, frameCount: frameCount)
        let (windowStates, segments) = resolveWindowStates(
            analysis: analysis,
            frameCount: frameCount,
            profile: profile
        )

        let lfeAvailable = labels.contains(where: isLFELabel)
        var fallbackReasons: [String] = []

        let impactChannels = selectImpactChannels(
            labels: labels,
            profiles: channelProfiles,
            fallbackReasons: &fallbackReasons
        )
        let textureChannels = selectTextureChannels(
            labels: labels,
            profiles: channelProfiles,
            fallbackReasons: &fallbackReasons
        )
        let rumbleChannels = selectRumbleChannels(
            labels: labels,
            profiles: channelProfiles,
            fallbackReasons: &fallbackReasons
        )

        let intensity = mergeWeighted(
            primary: rumbleChannels,
            secondary: impactChannels,
            primaryMix: profile == .speechFirst ? 0.45 : 0.65
        )
        let sharpness = mergeWeighted(
            primary: textureChannels,
            secondary: impactChannels,
            primaryMix: profile == .speechFirst ? 0.8 : 0.7
        )
        let transient = impactChannels

        var mapping = ChannelMapping(intensity: intensity, sharpness: sharpness, transient: transient)
        mapping = mapping.withFallbackResolved(using: labels)

        let ratio = stateRatio(states: windowStates)
        let recommendedSensitivity = clamp01(
            ratio.kickLead * defaultTransientSensitivity(for: .kickLead) +
            ratio.vocalLead * defaultTransientSensitivity(for: .vocalLead) +
            ratio.balanced * defaultTransientSensitivity(for: .balanced)
        )

        let diagnostics = DefaultHapticStrategyDiagnostics(
            kickLeadRatio: ratio.kickLead,
            vocalLeadRatio: ratio.vocalLead,
            balancedRatio: ratio.balanced,
            lfeAvailable: lfeAvailable,
            fallbackReasons: fallbackReasons
        )

        return DefaultHapticStrategyResult(
            mapping: mapping,
            recommendedTransientSensitivity: recommendedSensitivity,
            diagnostics: diagnostics,
            segments: segments
        )
    }

    public func impactRule(for state: DefaultHapticStrategyState) -> ClipTransientRule {
        switch state {
        case .kickLead:
            return ClipTransientRule(threshold: 0.45, cooldown: 0.08, gain: 1.20)
        case .vocalLead:
            return ClipTransientRule(threshold: 0.72, cooldown: 0.14, gain: 0.80)
        case .balanced:
            return ClipTransientRule(threshold: 0.55, cooldown: 0.10, gain: 1.00)
        }
    }

    public func texturePulse(for state: DefaultHapticStrategyState) -> (rate: Float, depth: Float) {
        switch state {
        case .kickLead:
            return (5.5, 0.30)
        case .vocalLead:
            return (4.0, 0.0)
        case .balanced:
            return (4.5, 0.25)
        }
    }

    public func textureStyle(for state: DefaultHapticStrategyState) -> TrackHapticStyle {
        switch state {
        case .vocalLead:
            return .continuous
        case .kickLead, .balanced:
            return .pulseTexture
        }
    }

    private func resolveWindowStates(
        analysis: MultiChannelAnalysisResult,
        frameCount: Int,
        profile: DefaultHapticProfile
    ) -> ([DefaultHapticStrategyState], [DefaultHapticStateSegment]) {
        let hop = Self.windowHop
        let duration = max(analysis.duration, hop)
        let windowCount = max(1, Int(ceil(duration / hop)))
        let overlapWindows = max(0, Int(ceil(Self.windowDuration / hop)) - 1)
        let lfeMask = analysis.channels.map { isLFELabel($0.label) }

        var windows = Array(repeating: WindowAccumulator(), count: windowCount)
        let frameTimes = analysis.channels[0].frames.prefix(frameCount).map(\.time)

        for frameIndex in 0..<frameCount {
            let time = frameTimes[frameIndex]
            let windowIndex = min(windowCount - 1, max(0, Int(time / hop)))

            for (channelIndex, channel) in analysis.channels.enumerated() {
                let frame = channel.frames[frameIndex]
                windows[windowIndex].accumulate(frame: frame, isLFE: lfeMask[channelIndex])
                if overlapWindows > 0 {
                    for offset in 1...overlapWindows where windowIndex >= offset {
                        windows[windowIndex - offset].accumulate(frame: frame, isLFE: lfeMask[channelIndex])
                    }
                }
            }
        }

        var states: [DefaultHapticStrategyState] = []
        states.reserveCapacity(windowCount)

        var currentState: DefaultHapticStrategyState = .balanced
        var lastSwitchTime: TimeInterval = 0

        for index in windows.indices {
            let normalized = windows[index].normalized
            let scores = stateScores(for: normalized, profile: profile)
            let candidate = candidateState(from: scores)
            let time = Double(index) * hop

            if states.isEmpty {
                currentState = candidate
                lastSwitchTime = time
                states.append(currentState)
                continue
            }

            let currentScore = score(of: currentState, from: scores)
            let candidateScore = score(of: candidate, from: scores)
            let canSwitch = (time - lastSwitchTime) >= Self.minHoldDuration && (candidateScore - currentScore) >= Self.switchDelta
            if candidate != currentState && canSwitch {
                currentState = candidate
                lastSwitchTime = time
            }
            states.append(currentState)
        }

        let segments = segmentsFrom(states: states, duration: duration, hop: hop)
        return (states, segments)
    }

    private func segmentsFrom(
        states: [DefaultHapticStrategyState],
        duration: TimeInterval,
        hop: TimeInterval
    ) -> [DefaultHapticStateSegment] {
        guard !states.isEmpty else {
            return [DefaultHapticStateSegment(state: .balanced, start: 0, end: duration)]
        }

        var output: [DefaultHapticStateSegment] = []
        var activeState = states[0]
        var activeStart: TimeInterval = 0

        for index in 1..<states.count {
            guard states[index] != activeState else { continue }
            let end = Double(index) * hop
            output.append(DefaultHapticStateSegment(state: activeState, start: activeStart, end: end))
            activeState = states[index]
            activeStart = end
        }

        output.append(DefaultHapticStateSegment(state: activeState, start: activeStart, end: duration))
        return output
    }

    private func stateScores(
        for window: NormalizedWindow,
        profile: DefaultHapticProfile
    ) -> (kick: Float, vocal: Float, rumble: Float) {
        let midProxy = clamp01(window.vocal + 0.5 * window.presence)

        var kickScore = clamp01(0.50 * window.kick + 0.35 * window.transient + 0.15 * window.low)
        var vocalScore = clamp01(0.55 * window.vocal + 0.25 * midProxy + 0.20 * (1 - window.transient))
        let rumbleScore = clamp01(0.60 * window.sub + 0.25 * window.low + 0.15 * window.lfePresence)

        switch profile {
        case .musicTrailer:
            kickScore = clamp01(kickScore + 0.04)
        case .speechFirst:
            vocalScore = clamp01(vocalScore + 0.08)
            kickScore = clamp01(kickScore - 0.04)
        case .balanced:
            break
        }

        return (kickScore, vocalScore, rumbleScore)
    }

    private func candidateState(from scores: (kick: Float, vocal: Float, rumble: Float)) -> DefaultHapticStrategyState {
        if scores.kick >= 0.58 && (scores.kick - scores.vocal) >= 0.08 {
            return .kickLead
        }
        if scores.vocal >= 0.56 && scores.kick < 0.45 {
            return .vocalLead
        }
        return .balanced
    }

    private func score(
        of state: DefaultHapticStrategyState,
        from scores: (kick: Float, vocal: Float, rumble: Float)
    ) -> Float {
        switch state {
        case .kickLead:
            return scores.kick
        case .vocalLead:
            return scores.vocal
        case .balanced:
            return clamp01((scores.kick + scores.vocal + scores.rumble) / 3)
        }
    }

    private func defaultTransientSensitivity(for state: DefaultHapticStrategyState) -> Float {
        switch state {
        case .kickLead:
            return 0.45
        case .vocalLead:
            return 0.72
        case .balanced:
            return 0.55
        }
    }

    private func stateRatio(states: [DefaultHapticStrategyState]) -> (kickLead: Float, vocalLead: Float, balanced: Float) {
        guard !states.isEmpty else {
            return (0, 0, 1)
        }
        let total = Float(states.count)
        let kick = Float(states.filter { $0 == .kickLead }.count) / total
        let vocal = Float(states.filter { $0 == .vocalLead }.count) / total
        let balanced = Float(states.filter { $0 == .balanced }.count) / total
        return (kick, vocal, balanced)
    }

    private func buildChannelProfiles(
        analysis: MultiChannelAnalysisResult,
        frameCount: Int
    ) -> [String: ChannelProfile] {
        var output: [String: ChannelProfile] = [:]
        let divisor = Float(max(1, frameCount))

        for channel in analysis.channels {
            var kick: Float = 0
            var low: Float = 0
            var sub: Float = 0
            var vocal: Float = 0
            var presence: Float = 0
            var transient: Float = 0

            for index in 0..<frameCount {
                let frame = channel.frames[index]
                kick += frame.bandEnergy.kick
                low += frame.bandEnergy.low
                sub += frame.bandEnergy.sub
                vocal += frame.bandEnergy.vocal
                presence += frame.bandEnergy.presence
                transient = max(transient, frame.transientStrength)
            }

            output[channel.label] = ChannelProfile(
                kick: clamp01(kick / divisor),
                low: clamp01(low / divisor),
                sub: clamp01(sub / divisor),
                vocal: clamp01(vocal / divisor),
                presence: clamp01(presence / divisor),
                transient: clamp01(transient)
            )
        }
        return output
    }

    private func selectImpactChannels(
        labels: [String],
        profiles: [String: ChannelProfile],
        fallbackReasons: inout [String]
    ) -> [ChannelWeight] {
        let kick = rankedWeights(
            labels: labels,
            profileMap: profiles,
            score: { $0.kick * 0.8 + $0.transient * 0.2 },
            minimum: 0.02
        )
        if !kick.isEmpty {
            return kick
        }
        fallbackReasons.append("impact:kick-unavailable")

        let vocalTransient = rankedWeights(
            labels: labels,
            profileMap: profiles,
            score: { ($0.vocal + 0.5 * $0.presence) * $0.transient },
            minimum: 0.015
        )
        if !vocalTransient.isEmpty {
            return vocalTransient
        }
        fallbackReasons.append("impact:vocal-transient-unavailable")

        let frontLabels = strictFrontLabels(from: labels)
        let front = rankedWeights(
            labels: frontLabels,
            profileMap: profiles,
            score: { $0.transient },
            minimum: 0.01
        )
        if !front.isEmpty {
            return front
        }
        fallbackReasons.append("impact:front-unavailable")

        return rankedWeights(
            labels: labels,
            profileMap: profiles,
            score: { $0.transient },
            minimum: 0
        )
    }

    private func selectTextureChannels(
        labels: [String],
        profiles: [String: ChannelProfile],
        fallbackReasons: inout [String]
    ) -> [ChannelWeight] {
        let vocal = rankedWeights(
            labels: labels,
            profileMap: profiles,
            score: { $0.vocal + 0.5 * $0.presence },
            minimum: 0.05
        )
        if !vocal.isEmpty {
            return vocal
        }
        fallbackReasons.append("texture:vocal-unavailable")

        let mid = rankedWeights(
            labels: labels,
            profileMap: profiles,
            score: { $0.vocal + 0.3 * $0.presence + 0.2 * $0.transient },
            minimum: 0.02
        )
        if !mid.isEmpty {
            return mid
        }
        fallbackReasons.append("texture:mid-unavailable")

        let frontLabels = strictFrontLabels(from: labels)
        let frontMid = rankedWeights(
            labels: frontLabels,
            profileMap: profiles,
            score: { $0.vocal + 0.3 * $0.presence + 0.2 * $0.transient },
            minimum: 0
        )
        if !frontMid.isEmpty {
            return frontMid
        }
        fallbackReasons.append("texture:front-unavailable")

        return rankedWeights(
            labels: labels,
            profileMap: profiles,
            score: { $0.vocal + 0.2 * $0.presence },
            minimum: 0
        )
    }

    private func selectRumbleChannels(
        labels: [String],
        profiles: [String: ChannelProfile],
        fallbackReasons: inout [String]
    ) -> [ChannelWeight] {
        let lfeLabels = labels.filter(isLFELabel)
        let lfe = rankedWeights(
            labels: lfeLabels,
            profileMap: profiles,
            score: { $0.sub + 0.5 * $0.low },
            minimum: 0.01
        )
        if !lfe.isEmpty {
            return lfe
        }
        fallbackReasons.append("rumble:lfe-unavailable")

        let frontLabels = strictFrontLabels(from: labels)
        let front = rankedWeights(
            labels: frontLabels,
            profileMap: profiles,
            score: { 0.7 * $0.low + 0.3 * $0.sub },
            minimum: 0
        )
        if !front.isEmpty {
            return front
        }
        fallbackReasons.append("rumble:front-unavailable")

        return rankedWeights(
            labels: labels,
            profileMap: profiles,
            score: { 0.7 * $0.low + 0.3 * $0.sub },
            minimum: 0
        )
    }

    private func rankedWeights(
        labels: [String],
        profileMap: [String: ChannelProfile],
        score: (ChannelProfile) -> Float,
        minimum: Float
    ) -> [ChannelWeight] {
        let ranked = labels.compactMap { label -> (String, Float)? in
            guard let profile = profileMap[label] else { return nil }
            let value = max(0, score(profile))
            guard value >= minimum else { return nil }
            return (label, value)
        }
        .sorted { $0.1 > $1.1 }

        guard !ranked.isEmpty else { return [] }
        let top = Array(ranked.prefix(4))
        let sum = top.reduce(Float(0)) { $0 + $1.1 }
        guard sum > 0 else { return [] }

        return top.map { ChannelWeight(channelLabel: $0.0, weight: $0.1 / sum) }
    }

    private func mergeWeighted(
        primary: [ChannelWeight],
        secondary: [ChannelWeight],
        primaryMix: Float
    ) -> [ChannelWeight] {
        var bag: [String: Float] = [:]
        for item in primary {
            bag[item.channelLabel, default: 0] += item.weight * primaryMix
        }
        for item in secondary {
            bag[item.channelLabel, default: 0] += item.weight * (1 - primaryMix)
        }
        return bag.map { ChannelWeight(channelLabel: $0.key, weight: $0.value) }
    }

    private func clamp01(_ value: Float) -> Float {
        max(0, min(1, value))
    }

    private func isLFELabel(_ label: String) -> Bool {
        label.uppercased().hasPrefix("LFE")
    }

    private func strictFrontLabels(from labels: [String]) -> [String] {
        let set = Set(labels)
        let candidates = ["L", "R", "C", "Lc", "Rc", "Lw", "Rw"]
        return candidates.filter { set.contains($0) }
    }
}

private struct ChannelProfile {
    let kick: Float
    let low: Float
    let sub: Float
    let vocal: Float
    let presence: Float
    let transient: Float
}

private struct WindowAccumulator {
    var sub: Float = 0
    var kick: Float = 0
    var low: Float = 0
    var vocal: Float = 0
    var presence: Float = 0
    var transient: Float = 0
    var sampleCount: Int = 0
    var lfeSub: Float = 0
    var lfeSampleCount: Int = 0

    mutating func accumulate(frame: ChannelFeatureFrame, isLFE: Bool) {
        sub += frame.bandEnergy.sub
        kick += frame.bandEnergy.kick
        low += frame.bandEnergy.low
        vocal += frame.bandEnergy.vocal
        presence += frame.bandEnergy.presence
        transient = max(transient, frame.transientStrength)
        sampleCount += 1
        if isLFE {
            lfeSub += frame.bandEnergy.sub
            lfeSampleCount += 1
        }
    }

    var normalized: NormalizedWindow {
        let divisor = Float(max(1, sampleCount))
        let lfeDivisor = Float(max(1, lfeSampleCount))
        return NormalizedWindow(
            sub: sub / divisor,
            kick: kick / divisor,
            low: low / divisor,
            vocal: vocal / divisor,
            presence: presence / divisor,
            transient: transient,
            lfePresence: lfeSub / lfeDivisor
        )
    }
}

private struct NormalizedWindow {
    let sub: Float
    let kick: Float
    let low: Float
    let vocal: Float
    let presence: Float
    let transient: Float
    let lfePresence: Float
}
