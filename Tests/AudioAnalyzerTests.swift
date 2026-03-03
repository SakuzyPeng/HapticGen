import XCTest
@testable import HapticGen

final class AudioAnalyzerTests: XCTestCase {
    func testAnalyzerProducesFramesForStereo() async throws {
        let url = try TestAudioFactory.makeStereoWAV(
            duration: 1.0,
            left: { frame, sr in
                let t = Double(frame) / sr
                return Float(sin(2 * .pi * 220 * t))
            },
            right: { frame, sr in
                let t = Double(frame) / sr
                return Float(sin(2 * .pi * 4000 * t))
            }
        )

        let analyzer = AudioAnalyzer()
        let result = try await analyzer.analyze(url: url)

        XCTAssertEqual(result.layout.type, .binaural2)
        XCTAssertEqual(result.channels.count, 2)
        XCTAssertFalse(result.channels[0].frames.isEmpty)

        let leftMean = result.channels[0].frames.map(\.spectralCentroidNorm).reduce(0, +) / Float(result.channels[0].frames.count)
        let rightMean = result.channels[1].frames.map(\.spectralCentroidNorm).reduce(0, +) / Float(result.channels[1].frames.count)

        XCTAssertGreaterThan(rightMean, leftMean)
        XCTAssertTrue(result.channels[0].frames.allSatisfy { $0.rms >= 0 && $0.rms <= 1 })
    }

    func testTransientDetectionFindsImpulses() async throws {
        let url = try TestAudioFactory.makeStereoWAV(
            duration: 1.0,
            left: { frame, sr in
                let pulseFrames = [Int(sr * 0.2), Int(sr * 0.5), Int(sr * 0.8)]
                return pulseFrames.contains(frame) ? 1.0 : 0.0
            },
            right: { _, _ in 0 }
        )

        let analyzer = AudioAnalyzer()
        let result = try await analyzer.analyze(url: url)

        let transientCount = result.channels[0].frames.filter(\.isTransient).count
        XCTAssertGreaterThanOrEqual(transientCount, 1)
    }
}
