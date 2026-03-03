import Foundation
import AVFoundation

enum TestAudioFactory {
    /// 生成多声道 WAV（用于基准测试），结果缓存在临时目录避免重复写入
    static func makeMultichannelWAV(
        channelCount: Int = 8,
        duration: TimeInterval = 60.0,
        sampleRate: Double = 48_000
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench_\(channelCount)ch_\(Int(duration))s_\(Int(sampleRate))hz.wav")

        if FileManager.default.fileExists(atPath: url.path) { return url }

        // 超过 2 声道的非交错格式必须提供显式 channel layout，否则 channels:interleaved: init 返回 nil
        let layoutTag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelCount)
        guard let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag) else {
            fatalError("无法创建 \(channelCount)ch 声道布局")
        }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: false,
            channelLayout: channelLayout
        )

        let frameCount = Int(duration * sampleRate)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            fatalError("Expected float channel data")
        }

        // 每个声道用不同频率的正弦波，每 2 秒叠加一个短暂冲击（触发瞬态检测）
        let freqs: [Float] = [40, 80, 120, 250, 500, 1000, 2000, 4000]
        for ch in 0..<channelCount {
            let freq = freqs[ch % freqs.count]
            for frame in 0..<frameCount {
                let t = Float(frame) / Float(sampleRate)
                var sample = 0.5 * sin(2 * .pi * freq * t)
                let tMod = t.truncatingRemainder(dividingBy: 2.0)
                if tMod < 0.002 { sample += 0.8 * sin(2 * .pi * 8000 * t) }
                channelData[ch][frame] = sample
            }
        }

        try file.write(from: buffer)
        return url
    }

    static func makeStereoWAV(
        duration: TimeInterval = 1.0,
        sampleRate: Double = 44_100,
        left: (_ frame: Int, _ sampleRate: Double) -> Float,
        right: (_ frame: Int, _ sampleRate: Double) -> Float
    ) throws -> URL {
        let frameCount = Int(duration * sampleRate)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else {
            fatalError("Expected float channel data")
        }

        for frame in 0..<frameCount {
            channelData[0][frame] = left(frame, sampleRate)
            channelData[1][frame] = right(frame, sampleRate)
        }

        try file.write(from: buffer)
        return url
    }
}
