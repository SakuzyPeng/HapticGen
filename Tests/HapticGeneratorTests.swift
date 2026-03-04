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

    func testGeneratorWithRegionMappingProducesResult() throws {
        var frames: [ChannelFeatureFrame] = []
        for index in 0..<200 {
            frames.append(ChannelFeatureFrame(
                time: Double(index) * 0.01,
                rms: Float(index % 10) / 10,
                spectralCentroidNorm: Float(index % 7) / 7,
                transientStrength: index % 20 == 0 ? 1.0 : 0.1,
                isTransient: index % 20 == 0
            ))
        }

        let analysis = MultiChannelAnalysisResult(
            duration: 2.0,
            sampleRate: 44_100,
            layout: ChannelLayout.detect(channelCount: 2),
            channels: [
                ChannelAnalysisResult(label: "L", frames: frames),
                ChannelAnalysisResult(label: "R", frames: frames)
            ]
        )

        let defaultMapping = ChannelMapping.defaults(for: analysis.layout)
        let lfeMapping = ChannelMapping(
            intensity: [ChannelWeight(channelLabel: "L", weight: 0.1)],
            sharpness: [ChannelWeight(channelLabel: "R", weight: 1.0)],
            transient: [ChannelWeight(channelLabel: "L", weight: 0.5)]
        )

        var regionMapping = TimeRegionMapping(defaultMapping: defaultMapping)
        regionMapping.addRegion(WeightRegion(startTime: 1.0, endTime: 2.0, mapping: lfeMapping))

        let generator = HapticGenerator()
        let descriptor = try generator.generate(
            from: analysis,
            regionMapping: regionMapping,
            settings: GeneratorSettings()
        )

        XCTAssertEqual(descriptor.duration, 2.0, accuracy: 0.001)
        XCTAssertFalse(descriptor.intensityCurvePoints.isEmpty)
        XCTAssertFalse(descriptor.sharpnessCurvePoints.isEmpty)
    }

    func testGeneratorRegionMappingProducesDifferentResultFromGlobal() throws {
        var frames: [ChannelFeatureFrame] = []
        for index in 0..<100 {
            frames.append(ChannelFeatureFrame(
                time: Double(index) * 0.01,
                rms: 0.8,
                spectralCentroidNorm: 0.5,
                transientStrength: 0,
                isTransient: false
            ))
        }
        var framesB: [ChannelFeatureFrame] = []
        for index in 0..<100 {
            framesB.append(ChannelFeatureFrame(
                time: Double(index) * 0.01,
                rms: 0.1,  // 声道 R 的 rms 明显低于 L
                spectralCentroidNorm: 0.5,
                transientStrength: 0,
                isTransient: false
            ))
        }

        let analysis = MultiChannelAnalysisResult(
            duration: 1.0,
            sampleRate: 44_100,
            layout: ChannelLayout.detect(channelCount: 2),
            channels: [
                ChannelAnalysisResult(label: "L", frames: frames),
                ChannelAnalysisResult(label: "R", frames: framesB)
            ]
        )

        let labels = analysis.channels.map(\.label)
        let lHeavy = ChannelMapping(
            intensity: [ChannelWeight(channelLabel: "L", weight: 1.0)],
            sharpness: [ChannelWeight(channelLabel: "L", weight: 1.0)],
            transient: []
        ).withFallbackResolved(using: labels)

        let rHeavy = ChannelMapping(
            intensity: [ChannelWeight(channelLabel: "R", weight: 1.0)],
            sharpness: [ChannelWeight(channelLabel: "R", weight: 1.0)],
            transient: []
        ).withFallbackResolved(using: labels)

        let generator = HapticGenerator()
        let descL = try generator.generate(from: analysis, mapping: lHeavy, settings: GeneratorSettings())
        let descR = try generator.generate(from: analysis, mapping: rHeavy, settings: GeneratorSettings())

        // L 权重生成的强度曲线均值应高于 R 权重（L 的 rms 更高）
        let avgIntensityL = descL.intensityCurvePoints.map(\.value).reduce(0, +) / Float(descL.intensityCurvePoints.count)
        let avgIntensityR = descR.intensityCurvePoints.map(\.value).reduce(0, +) / Float(descR.intensityCurvePoints.count)
        XCTAssertGreaterThan(avgIntensityL, avgIntensityR)
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
