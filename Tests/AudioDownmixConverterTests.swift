import XCTest
import AVFoundation
@testable import HapticGen

final class AudioDownmixConverterTests: XCTestCase {

    private let converter = AudioDownmixConverter()

    // MARK: - 8ch 44100 → 2ch 44100

    func testMultichannelInputProducesStereo44kOutput() throws {
        let inputURL = try TestAudioFactory.makeMultichannelWAV(
            channelCount: 8, duration: 0.5, sampleRate: 44_100
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")

        try converter.makeStereo44100(inputURL: inputURL, outputURL: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "输出文件应存在")

        let outFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(outFile.processingFormat.channelCount, 2, "输出应为 2ch")
        XCTAssertEqual(outFile.processingFormat.sampleRate, 44_100, "采样率应为 44100")
        XCTAssertGreaterThan(outFile.length, 0, "输出文件不应为空")
    }

    // MARK: - 1ch 22050 → 2ch 44100，双声道相同

    func testMonoInputDuplicatesToBothStereoChannels() throws {
        // 生成单声道 22050Hz 正弦波
        let sampleRate: Double = 22_050
        let duration: TimeInterval = 0.2
        let frameCount = Int(sampleRate * duration)
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        // 在独立作用域内写文件，确保句柄关闭（WAV header 最终化）后再读取
        try {
            let inFile = try AVAudioFile(forWriting: inputURL, settings: monoFormat.settings)
            let inBuf = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frameCount))!
            inBuf.frameLength = AVAudioFrameCount(frameCount)
            for i in 0..<frameCount {
                inBuf.floatChannelData![0][i] = Float(sin(Double(i) / sampleRate * 440 * 2 * .pi))
            }
            try inFile.write(from: inBuf)
        }()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        try converter.makeStereo44100(inputURL: inputURL, outputURL: outputURL)

        let outFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(outFile.processingFormat.channelCount, 2, "输出应为 2ch")
        XCTAssertEqual(outFile.processingFormat.sampleRate, 44_100, "输出应为 44100Hz")

        // 读取输出验证两个声道相同
        let readBuf = AVAudioPCMBuffer(
            pcmFormat: outFile.processingFormat,
            frameCapacity: AVAudioFrameCount(outFile.length)
        )!
        try outFile.read(into: readBuf)
        XCTAssertGreaterThan(readBuf.frameLength, 0)

        let l = Array(UnsafeBufferPointer(start: readBuf.floatChannelData![0], count: Int(readBuf.frameLength)))
        let r = Array(UnsafeBufferPointer(start: readBuf.floatChannelData![1], count: Int(readBuf.frameLength)))
        // 采样一小段对比（前100帧）
        let sampleCount = min(100, l.count)
        for i in 0..<sampleCount {
            XCTAssertEqual(l[i], r[i], accuracy: 1e-5, "两声道第\(i)帧应相同")
        }
    }

    // MARK: - 2ch 48k → 2ch 44100

    func testStereo48kResampledTo44100() throws {
        let inputURL = try TestAudioFactory.makeStereoWAV(
            duration: 0.3, sampleRate: 48_000,
            left: { frame, sr in Float(sin(Double(frame) / sr * 440 * 2 * .pi)) },
            right: { frame, sr in Float(cos(Double(frame) / sr * 440 * 2 * .pi)) }
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")

        try converter.makeStereo44100(inputURL: inputURL, outputURL: outputURL)

        let outFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(outFile.processingFormat.channelCount, 2)
        XCTAssertEqual(outFile.processingFormat.sampleRate, 44_100)
        XCTAssertGreaterThan(outFile.length, 0)
    }
}
