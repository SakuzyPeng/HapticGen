import Foundation
import AVFoundation

/// 音频格式转换：任意声道 / 任意采样率 → stereo 44.1kHz Float32 PCM WAV
final class AudioDownmixConverter: AudioPreprocessing, @unchecked Sendable {

    private let blockFrames: AVAudioFrameCount = 4096

    @discardableResult
    func makeStereo44100(inputURL: URL, outputURL: URL) throws -> URL {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = inputFile.processingFormat

        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else {
            throw AudioHapticError.separationFailed("Cannot create stereo 44.1kHz format")
        }

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: stereoFormat.settings)

        if inputFormat.channelCount == 1 {
            try convertMono(inputFile: inputFile, inputFormat: inputFormat,
                            outputFile: outputFile, stereoFormat: stereoFormat)
        } else {
            try convertMultichannel(inputFile: inputFile, inputFormat: inputFormat,
                                    outputFile: outputFile, stereoFormat: stereoFormat)
        }

        return outputURL
    }

    // MARK: - Mono → Stereo 44.1kHz

    private func convertMono(
        inputFile: AVAudioFile,
        inputFormat: AVAudioFormat,
        outputFile: AVAudioFile,
        stereoFormat: AVAudioFormat
    ) throws {
        // Step 1: resample mono → mono@44100
        let mono44k = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let converter = AVAudioConverter(from: inputFormat, to: mono44k) else {
            throw AudioHapticError.separationFailed("Cannot create mono→mono@44k converter")
        }

        var reachedEnd = false
        while !reachedEnd {
            guard let monoBuf = AVAudioPCMBuffer(pcmFormat: mono44k, frameCapacity: blockFrames) else { break }

            var convError: NSError?
            let status = converter.convert(to: monoBuf, error: &convError) { [weak inputFile] frameCount, outStatus in
                guard frameCount > 0,
                      let inputFile,
                      let inBuf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                try? inputFile.read(into: inBuf, frameCount: frameCount)
                if inBuf.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                } else {
                    outStatus.pointee = .haveData
                }
                return inBuf
            }

            if let e = convError { throw e }

            if monoBuf.frameLength > 0 {
                // Step 2: duplicate mono samples → both stereo channels
                guard let stereoBuf = AVAudioPCMBuffer(pcmFormat: stereoFormat,
                                                       frameCapacity: monoBuf.frameLength) else { break }
                stereoBuf.frameLength = monoBuf.frameLength
                let n = Int(monoBuf.frameLength)
                if let src = monoBuf.floatChannelData?[0],
                   let dstL = stereoBuf.floatChannelData?[0],
                   let dstR = stereoBuf.floatChannelData?[1] {
                    memcpy(dstL, src, n * MemoryLayout<Float>.size)
                    memcpy(dstR, src, n * MemoryLayout<Float>.size)
                }
                try outputFile.write(from: stereoBuf)
            }

            if status == .endOfStream { reachedEnd = true }
        }
    }

    // MARK: - Stereo / Multichannel → Stereo 44.1kHz

    private func convertMultichannel(
        inputFile: AVAudioFile,
        inputFormat: AVAudioFormat,
        outputFile: AVAudioFile,
        stereoFormat: AVAudioFormat
    ) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: stereoFormat) else {
            throw AudioHapticError.separationFailed("Cannot create multichannel→stereo converter")
        }

        // For > 2 channels: take first 2 channels as L/R
        if inputFormat.channelCount > 2 {
            converter.channelMap = [0, 1]
        }

        var reachedEnd = false
        while !reachedEnd {
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: blockFrames) else { break }

            var convError: NSError?
            let status = converter.convert(to: outBuf, error: &convError) { [weak inputFile] frameCount, outStatus in
                guard frameCount > 0,
                      let inputFile,
                      let inBuf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                try? inputFile.read(into: inBuf, frameCount: frameCount)
                if inBuf.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                } else {
                    outStatus.pointee = .haveData
                }
                return inBuf
            }

            if let e = convError { throw e }
            if outBuf.frameLength > 0 { try outputFile.write(from: outBuf) }
            if status == .endOfStream { reachedEnd = true }
        }
    }
}
