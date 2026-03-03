import XCTest
@testable import HapticGen

final class DefaultHapticStrategyResolverTests: XCTestCase {
    func testResolverClassifiesKickLeadAndProducesImpactMapping() {
        let analysis = makeAnalysis(
            duration: 4.0,
            channelLabels: ["L", "R", "LFE"],
            state: .kickLead
        )

        let resolver = DefaultHapticStrategyResolver()
        let result = resolver.resolve(analysis: analysis, profile: .musicTrailer)

        XCTAssertGreaterThan(result.diagnostics.kickLeadRatio, 0.6)
        XCTAssertLessThan(result.recommendedTransientSensitivity, 0.6)
        XCTAssertFalse(result.mapping.transient.isEmpty)
        XCTAssertTrue(result.mapping.transient.contains { $0.channelLabel == "LFE" || $0.channelLabel == "L" || $0.channelLabel == "R" })
    }

    func testResolverClassifiesVocalLeadWhenKickIsWeak() {
        let analysis = makeAnalysis(
            duration: 4.0,
            channelLabels: ["L", "R"],
            state: .vocalLead
        )

        let resolver = DefaultHapticStrategyResolver()
        let result = resolver.resolve(analysis: analysis, profile: .speechFirst)

        XCTAssertGreaterThan(result.diagnostics.vocalLeadRatio, 0.6)
        XCTAssertGreaterThanOrEqual(result.recommendedTransientSensitivity, 0.6)
    }

    func testResolverRumbleFallbackWhenLFEUnavailable() {
        let analysis = makeAnalysis(
            duration: 2.0,
            channelLabels: ["L", "R", "C"],
            state: .balanced
        )

        let resolver = DefaultHapticStrategyResolver()
        let result = resolver.resolve(analysis: analysis, profile: .balanced)

        XCTAssertFalse(result.diagnostics.lfeAvailable)
        XCTAssertTrue(result.diagnostics.fallbackReasons.contains(where: { $0.contains("rumble:lfe-unavailable") }))
        XCTAssertFalse(result.mapping.intensity.isEmpty)
    }

    func testResolverFallbackChainReachesAllWhenNoFrontOrLFE() {
        let analysis = makeAnalysis(
            duration: 2.0,
            channelLabels: ["Ch1", "Ch2", "Ch3"],
            state: .balanced
        )

        let resolver = DefaultHapticStrategyResolver()
        let result = resolver.resolve(analysis: analysis, profile: .balanced)

        XCTAssertTrue(result.diagnostics.fallbackReasons.contains("rumble:lfe-unavailable"))
        XCTAssertTrue(result.diagnostics.fallbackReasons.contains("rumble:front-unavailable"))
        XCTAssertFalse(result.mapping.intensity.isEmpty)
        XCTAssertFalse(result.mapping.transient.isEmpty)
    }

    func testResolverMinHoldPreventsRapidStateFlapping() {
        let analysis = makeAnalysis(
            duration: 1.0,
            channelLabels: ["L", "R"],
            stateAtTime: { time in
                let bucket = Int(time / 0.1)
                return bucket.isMultiple(of: 2) ? .kickLead : .vocalLead
            }
        )

        let resolver = DefaultHapticStrategyResolver()
        let result = resolver.resolve(analysis: analysis, profile: .balanced)

        XCTAssertEqual(result.segments.count, 1)
    }

    func testChannelMappingDefaultsOverloadUsesStrategy() {
        let analysis = makeAnalysis(
            duration: 3.0,
            channelLabels: ["L", "R", "C", "LFE", "Ls", "Rs", "Rls", "Rrs"],
            state: .kickLead
        )

        let mapping = ChannelMapping.defaults(for: analysis.layout, analysis: analysis, profile: .musicTrailer)
        XCTAssertFalse(mapping.intensity.isEmpty)
        XCTAssertFalse(mapping.sharpness.isEmpty)
        XCTAssertFalse(mapping.transient.isEmpty)
    }

    func testTimelineDefaultBuildsSegmentedClipsFromStrategy() {
        let analysis = makeAnalysis(
            duration: 3.0,
            channelLabels: ["L", "R", "C", "LFE"],
            state: .balanced
        )

        let strategy = DefaultHapticStrategyResult(
            mapping: ChannelMapping.defaults(for: analysis.layout),
            recommendedTransientSensitivity: 0.55,
            diagnostics: DefaultHapticStrategyDiagnostics(
                kickLeadRatio: 0.4,
                vocalLeadRatio: 0.3,
                balancedRatio: 0.3,
                lfeAvailable: true,
                fallbackReasons: []
            ),
            segments: [
                DefaultHapticStateSegment(state: .kickLead, start: 0, end: 1.0),
                DefaultHapticStateSegment(state: .vocalLead, start: 1.0, end: 2.0),
                DefaultHapticStateSegment(state: .balanced, start: 2.0, end: 3.0)
            ]
        )

        let document = HapticTimelineDocument.default(for: analysis, template: .trailer, strategy: strategy)
        XCTAssertEqual(document.tracks.count, 3)
        XCTAssertEqual(document.tracks[2].clips.count, 3)

        let impactRules = document.tracks[2].clips.map(\.transientRule)
        XCTAssertEqual(impactRules[0].threshold, 0.45, accuracy: 0.001)
        XCTAssertEqual(impactRules[1].threshold, 0.72, accuracy: 0.001)
        XCTAssertEqual(impactRules[2].threshold, 0.55, accuracy: 0.001)
    }

    private func makeAnalysis(
        duration: TimeInterval,
        channelLabels: [String],
        state: DefaultHapticStrategyState
    ) -> MultiChannelAnalysisResult {
        makeAnalysis(
            duration: duration,
            channelLabels: channelLabels,
            stateAtTime: { _ in state }
        )
    }

    private func makeAnalysis(
        duration: TimeInterval,
        channelLabels: [String],
        stateAtTime: (TimeInterval) -> DefaultHapticStrategyState
    ) -> MultiChannelAnalysisResult {
        let frameStep = 0.01
        let frameCount = max(1, Int(duration / frameStep))

        func frame(at time: TimeInterval) -> ChannelFeatureFrame {
            let state = stateAtTime(time)
            switch state {
            case .kickLead:
                return ChannelFeatureFrame(
                    time: time,
                    rms: 0.7,
                    spectralCentroidNorm: 0.35,
                    transientStrength: 0.85,
                    isTransient: true,
                    bandEnergy: SpectralBandEnergy(sub: 0.20, kick: 0.60, low: 0.45, vocal: 0.08, presence: 0.05)
                )
            case .vocalLead:
                return ChannelFeatureFrame(
                    time: time,
                    rms: 0.55,
                    spectralCentroidNorm: 0.45,
                    transientStrength: 0.20,
                    isTransient: false,
                    bandEnergy: SpectralBandEnergy(sub: 0.05, kick: 0.08, low: 0.10, vocal: 0.55, presence: 0.35)
                )
            case .balanced:
                return ChannelFeatureFrame(
                    time: time,
                    rms: 0.5,
                    spectralCentroidNorm: 0.4,
                    transientStrength: 0.45,
                    isTransient: false,
                    bandEnergy: SpectralBandEnergy(sub: 0.12, kick: 0.22, low: 0.20, vocal: 0.25, presence: 0.18)
                )
            }
        }

        let channels = channelLabels.map { label -> ChannelAnalysisResult in
            var frames: [ChannelFeatureFrame] = []
            frames.reserveCapacity(frameCount)
            for index in 0..<frameCount {
                frames.append(frame(at: Double(index) * frameStep))
            }
            return ChannelAnalysisResult(label: label, frames: frames)
        }

        return MultiChannelAnalysisResult(
            duration: duration,
            sampleRate: 48_000,
            layout: ChannelLayout.detect(channelCount: channelLabels.count),
            channels: channels
        )
    }
}
