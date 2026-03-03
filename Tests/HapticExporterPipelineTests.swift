import XCTest
import Foundation
@testable import HapticGen

final class HapticExporterPipelineTests: XCTestCase {
    func testExporterCreatesValidAHAPJSON() throws {
        let descriptor = HapticPatternDescriptor(
            duration: 1.0,
            continuousEvent: ContinuousEventDescriptor(duration: 1.0),
            intensityCurvePoints: [CurvePoint(time: 0, value: 0.2), CurvePoint(time: 1.0, value: 0.8)],
            sharpnessCurvePoints: [CurvePoint(time: 0, value: 0.3), CurvePoint(time: 1.0, value: 0.6)],
            transientEvents: [TransientPoint(time: 0.5, intensity: 1.0, sharpness: 0.8)]
        )

        let exporter = HapticExporter()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ahap")

        try exporter.exportAHAP(descriptor, to: output)

        let data = try Data(contentsOf: output)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let dictionary = try XCTUnwrap(jsonObject as? [String: Any])

        XCTAssertEqual(dictionary["Version"] as? Int, 1)
        XCTAssertNotNil(dictionary["Pattern"] as? [[String: Any]])
    }

    func testEndToEndAnalyzeGenerateExportAndReload() async throws {
        let url = try TestAudioFactory.makeStereoWAV(
            duration: 1.2,
            left: { frame, sr in
                let t = Double(frame) / sr
                return Float(0.8 * sin(2 * .pi * 200 * t))
            },
            right: { frame, sr in
                let t = Double(frame) / sr
                return Float(0.8 * sin(2 * .pi * 1000 * t))
            }
        )

        let analyzer = AudioAnalyzer()
        let result = try await analyzer.analyze(url: url)

        let generator = HapticGenerator()
        let descriptor = try generator.generate(
            from: result,
            mapping: ChannelMapping.defaults(for: result.layout),
            settings: GeneratorSettings()
        )

        let exporter = HapticExporter()
        _ = try exporter.makePattern(descriptor)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ahap")
        try exporter.exportAHAP(descriptor, to: output)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertGreaterThan((try Data(contentsOf: output)).count, 0)
    }
}
