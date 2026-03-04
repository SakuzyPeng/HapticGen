import XCTest
@testable import HapticGen

final class HapticGeneratorTests: XCTestCase {
    func testGeneratorProducesCoreStructure() throws {
        var frames: [ChannelFeatureFrame] = []
        frames.reserveCapacity(100)
        for index in 0..<100 {
            let frame = ChannelFeatureFrame(
                time: Double(index) * 0.01,
                rms: Float(index % 10) / 10,
                spectralCentroidNorm: Float(index % 7) / 7,
                transientStrength: index % 20 == 0 ? 1.0 : 0.1,
                isTransient: index % 20 == 0
            )
            frames.append(frame)
        }

        let analysis = MultiChannelAnalysisResult(
            duration: 1.0,
            sampleRate: 44_100,
            layout: ChannelLayout.detect(channelCount: 2),
            channels: [
                ChannelAnalysisResult(label: "L", frames: frames),
                ChannelAnalysisResult(label: "R", frames: frames)
            ]
        )

        let generator = HapticGenerator()
        let descriptor = try generator.generate(
            from: analysis,
            mapping: ChannelMapping.defaults(for: analysis.layout),
            settings: GeneratorSettings()
        )

        XCTAssertEqual(descriptor.continuousEvent.duration, analysis.duration)
        XCTAssertFalse(descriptor.intensityCurvePoints.isEmpty)
        XCTAssertFalse(descriptor.sharpnessCurvePoints.isEmpty)
        XCTAssertFalse(descriptor.transientEvents.isEmpty)
    }

    func testGeneratorEnforcesCurvePointLimit() throws {
        let frameCount = 70_000
        var frames: [ChannelFeatureFrame] = []
        frames.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            let frame = ChannelFeatureFrame(
                time: Double(index) * 0.001,
                rms: 0.6,
                spectralCentroidNorm: 0.4,
                transientStrength: 0,
                isTransient: false
            )
            frames.append(frame)
        }

        let analysis = MultiChannelAnalysisResult(
            duration: 70,
            sampleRate: 44_100,
            layout: ChannelLayout.detect(channelCount: 2),
            channels: [
                ChannelAnalysisResult(label: "L", frames: frames),
                ChannelAnalysisResult(label: "R", frames: frames)
            ]
        )

        let generator = HapticGenerator()
        let descriptor = try generator.generate(
            from: analysis,
            mapping: ChannelMapping.defaults(for: analysis.layout),
            settings: GeneratorSettings(eventDensity: 3.0)
        )

        XCTAssertLessThanOrEqual(descriptor.intensityCurvePoints.count, 16_384)
        XCTAssertLessThanOrEqual(descriptor.sharpnessCurvePoints.count, 16_384)
    }
}
