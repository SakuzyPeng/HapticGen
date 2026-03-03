import XCTest
import Foundation
import CoreHaptics
@testable import HapticGen

final class RealAudioAHAPIntegrationTests: XCTestCase {
    func testGenerateAHAPFromReal8chSample() async throws {
        let sampleInfo = try resolveSamplePath()

        let analyzer = AudioAnalyzer()
        let result: MultiChannelAnalysisResult
        do {
            result = try await analyzer.analyze(url: sampleInfo.url)
        } catch {
            XCTFail("分析失败: \(error.localizedDescription)")
            throw error
        }

        let expectedChannels = expectedChannelCount(defaultValue: 8)
        XCTAssertEqual(result.channels.count, expectedChannels, "声道数不匹配")
        XCTAssertEqual(result.layout.type, .surround71_8, "布局识别应为 7.1")
        XCTAssertGreaterThan(result.duration, 300)
        XCTAssertLessThan(result.duration, 340)

        let mapping = ChannelMapping.defaults(for: result.layout)
        let generator = HapticGenerator()
        let descriptor: HapticPatternDescriptor
        do {
            descriptor = try generator.generate(
                from: result,
                mapping: mapping,
                settings: GeneratorSettings(transientSensitivity: 0.0)
            )
        } catch {
            XCTFail("生成失败: \(error.localizedDescription)")
            throw error
        }

        XCTAssertGreaterThan(descriptor.intensityCurvePoints.count, 100)
        XCTAssertGreaterThan(descriptor.sharpnessCurvePoints.count, 100)
        XCTAssertLessThanOrEqual(descriptor.intensityCurvePoints.count, 16_384)
        XCTAssertLessThanOrEqual(descriptor.sharpnessCurvePoints.count, 16_384)
        XCTAssertGreaterThan(descriptor.transientEvents.count, 0)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("real-audio-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ahap")

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let exporter = HapticExporter()
        do {
            try exporter.exportAHAP(descriptor, to: outputURL)
        } catch {
            XCTFail("导出失败: \(error.localizedDescription)")
            throw error
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "导出文件不存在")
        let ahapData = try Data(contentsOf: outputURL)
        XCTAssertGreaterThan(ahapData.count, 0, "导出文件为空")

        let ahapObject = try JSONSerialization.jsonObject(with: ahapData)
        let ahapDictionary = try XCTUnwrap(ahapObject as? [String: Any])
        XCTAssertEqual(ahapDictionary["Version"] as? Int, 1)

        let pattern = try XCTUnwrap(ahapDictionary["Pattern"] as? [[String: Any]])
        XCTAssertFalse(pattern.isEmpty)

        let containsContinuous = pattern.contains { entry in
            guard let event = entry["Event"] as? [String: Any] else { return false }
            return (event["EventType"] as? String) == "HapticContinuous"
        }
        XCTAssertTrue(containsContinuous, "应包含 HapticContinuous")

        let curveIDs = pattern.compactMap { entry -> String? in
            guard let curve = entry["ParameterCurve"] as? [String: Any] else { return nil }
            return curve["ParameterID"] as? String
        }

        XCTAssertTrue(curveIDs.contains("HapticIntensityControl"), "应包含强度曲线")
        XCTAssertTrue(curveIDs.contains("HapticSharpnessControl"), "应包含锐度曲线")

        do {
            _ = try exporter.makePattern(descriptor)
            _ = try CHHapticPattern(contentsOf: outputURL)
        } catch {
            XCTFail("AHAP 回读失败: \(error.localizedDescription)")
            throw error
        }

        print("[RealAudioAHAPIntegrationTests] sample=\(sampleInfo.url.path)")
        print("[RealAudioAHAPIntegrationTests] channels=\(result.channels.count), duration=\(result.duration)")
        print("[RealAudioAHAPIntegrationTests] output=\(outputURL.path)")
        print("[RealAudioAHAPIntegrationTests] intensityPoints=\(descriptor.intensityCurvePoints.count), sharpnessPoints=\(descriptor.sharpnessCurvePoints.count), transients=\(descriptor.transientEvents.count)")
    }

    private func resolveSamplePath() throws -> (url: URL, fromEnv: Bool) {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["AUDIO_SAMPLE_PATH"], !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: explicit)
            guard FileManager.default.fileExists(atPath: url.path) else {
                XCTFail("AUDIO_SAMPLE_PATH 指向的文件不存在: \(url.path)")
                throw NSError(domain: "RealAudioAHAPIntegrationTests", code: 1)
            }
            return (url, true)
        }

        let defaultURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("aduio")
            .appendingPathComponent("8ch样本.flac")

        guard FileManager.default.fileExists(atPath: defaultURL.path) else {
            throw XCTSkip("未设置 AUDIO_SAMPLE_PATH 且默认样本不存在: \(defaultURL.path)")
        }

        return (defaultURL, false)
    }

    private func expectedChannelCount(defaultValue: Int) -> Int {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["AUDIO_EXPECTED_CHANNELS"], let value = Int(raw), value > 0 {
            return value
        }
        return defaultValue
    }
}
