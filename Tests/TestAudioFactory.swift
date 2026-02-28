import Foundation
import AVFoundation

enum TestAudioFactory {
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
