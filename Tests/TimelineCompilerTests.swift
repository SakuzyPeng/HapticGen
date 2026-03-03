import XCTest
@testable import HapticGen

final class TimelineCompilerTests: XCTestCase {
    func testCompileProducesValidDescriptorFromDefaultTimeline() throws {
        let analysis = makeSyntheticAnalysis(frameCount: 300, frameStep: 0.01)
        var document = HapticTimelineDocument.default(for: analysis.layout, duration: analysis.duration, template: .action)
        if let impactIndex = document.tracks.firstIndex(where: { $0.style == .transientBurst }),
           let clipIndex = document.tracks[impactIndex].clips.indices.first {
            document.tracks[impactIndex].clips[clipIndex].transientRule.threshold = 0.05
            document.tracks[impactIndex].clips[clipIndex].transientRule.gain = 2.0
        }

        let compiler = TimelineCompiler()
        let descriptor = try compiler.compile(
            document: document,
            analysis: analysis,
            settings: .init(transientSensitivity: 0)
        )

        XCTAssertGreaterThan(descriptor.intensityCurvePoints.count, 10)
        XCTAssertGreaterThan(descriptor.sharpnessCurvePoints.count, 10)
        XCTAssertGreaterThan(descriptor.transientEvents.count, 0)
        XCTAssertLessThanOrEqual(descriptor.intensityCurvePoints.count, HapticExporter.maxControlPointCount)
        XCTAssertLessThanOrEqual(descriptor.sharpnessCurvePoints.count, HapticExporter.maxControlPointCount)
    }

    func testCompileWindowReturnsWindowRelativeTimes() throws {
        let analysis = makeSyntheticAnalysis(frameCount: 500, frameStep: 0.01)
        let document = HapticTimelineDocument.default(for: analysis.layout, duration: analysis.duration, template: .trailer)

        let compiler = TimelineCompiler()
        let descriptor = try compiler.compileWindow(
            document: document,
            analysis: analysis,
            settings: .init(),
            timeRange: 1.0...2.5
        )

        XCTAssertGreaterThan(descriptor.duration, 1.4)
        XCTAssertLessThanOrEqual(descriptor.duration, 1.6)
        XCTAssertTrue(descriptor.intensityCurvePoints.allSatisfy { $0.time >= 0 && $0.time <= descriptor.duration })
        XCTAssertTrue(descriptor.sharpnessCurvePoints.allSatisfy { $0.time >= 0 && $0.time <= descriptor.duration })
        XCTAssertTrue(descriptor.transientEvents.allSatisfy { $0.time >= 0 && $0.time <= descriptor.duration })
    }

    func testCompileWithUnmatchedCustomChannelGroupFallsBackGracefully() throws {
        let analysis = makeSyntheticAnalysis(frameCount: 200, frameStep: 0.02)
        var document = HapticTimelineDocument.default(for: analysis.layout, duration: analysis.duration, template: .music)

        guard !document.tracks.isEmpty else {
            XCTFail("Expected default tracks")
            return
        }

        document.tracks[0].source.channelGroup = ChannelGroup(kind: .custom, customLabels: ["Nope1", "Nope2"])

        let compiler = TimelineCompiler()
        let descriptor = try compiler.compile(document: document, analysis: analysis, settings: .init())

        XCTAssertFalse(descriptor.intensityCurvePoints.isEmpty)
        XCTAssertFalse(descriptor.sharpnessCurvePoints.isEmpty)
    }

    func testTimelineCompileExportReloadEndToEnd() throws {
        let analysis = makeSyntheticAnalysis(frameCount: 240, frameStep: 0.01)
        let document = HapticTimelineDocument.default(for: analysis.layout, duration: analysis.duration, template: .trailer)
        let compiler = TimelineCompiler()
        let descriptor = try compiler.compile(document: document, analysis: analysis, settings: .init())

        let exporter = HapticExporter()
        _ = try exporter.makePattern(descriptor)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ahap")

        try exporter.exportAHAP(descriptor, to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testCompileAppliesTransientGuardrails() throws {
        let analysis = makeSyntheticAnalysis(frameCount: 600, frameStep: 0.01)
        var document = HapticTimelineDocument.default(for: analysis.layout, duration: analysis.duration, template: .action)

        if let impactIndex = document.tracks.firstIndex(where: { $0.style == .transientBurst }),
           let clipIndex = document.tracks[impactIndex].clips.indices.first {
            document.tracks[impactIndex].clips[clipIndex].transientRule.threshold = 0.01
            document.tracks[impactIndex].clips[clipIndex].transientRule.cooldown = 0
            document.tracks[impactIndex].clips[clipIndex].transientRule.gain = 2
        }

        let descriptor = try TimelineCompiler().compile(
            document: document,
            analysis: analysis,
            settings: GeneratorSettings(transientSensitivity: 0, transientMinInterval: 0.08, transientMaxPerSecond: 8)
        )

        for index in 1..<descriptor.transientEvents.count {
            let delta = descriptor.transientEvents[index].time - descriptor.transientEvents[index - 1].time
            XCTAssertGreaterThanOrEqual(delta, 0.079)
        }
    }

    private func makeSyntheticAnalysis(frameCount: Int, frameStep: TimeInterval) -> MultiChannelAnalysisResult {
        var left: [ChannelFeatureFrame] = []
        var right: [ChannelFeatureFrame] = []

        left.reserveCapacity(frameCount)
        right.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let t = TimeInterval(i) * frameStep
            let phase = Float(i) / Float(max(frameCount - 1, 1))
            let baseRMS = 0.2 + 0.7 * phase
            let centroid = min(1, 0.15 + 0.75 * phase)
            let transient: Float = i % 35 == 0 ? 0.95 : 0.1

            left.append(ChannelFeatureFrame(
                time: t,
                rms: min(1, baseRMS),
                spectralCentroidNorm: centroid,
                transientStrength: transient,
                isTransient: transient > 0.9
            ))

            right.append(ChannelFeatureFrame(
                time: t,
                rms: min(1, baseRMS * 0.9),
                spectralCentroidNorm: min(1, centroid + 0.05),
                transientStrength: max(0, transient - 0.05),
                isTransient: transient > 0.9
            ))
        }

        let duration = TimeInterval(max(frameCount - 1, 1)) * frameStep

        return MultiChannelAnalysisResult(
            duration: duration,
            sampleRate: 48_000,
            layout: .detect(channelCount: 2),
            channels: [
                ChannelAnalysisResult(label: "L", frames: left),
                ChannelAnalysisResult(label: "R", frames: right)
            ]
        )
    }
}
