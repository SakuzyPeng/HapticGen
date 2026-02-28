import Foundation
import AVFoundation
import Accelerate

public final class AudioAnalyzer: @unchecked Sendable {
    public init() {}

    public func analyze(
        url: URL,
        settings: AnalyzerSettings = AnalyzerSettings(),
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> MultiChannelAnalysisResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)

        guard channelCount > 0, sampleRate > 0 else {
            throw AudioHapticError.invalidAudioFormat
        }

        let layout = ChannelLayout.detect(channelCount: channelCount)
        let totalFrames = max(Int(file.length), 1)
        let blockFrames = max(settings.fftSize, Int(sampleRate * settings.blockDuration))

        let log2n = vDSP_Length(log2(Float(settings.fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw AudioHapticError.invalidAnalysis("无法创建 FFT setup")
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let hannWindow = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: settings.fftSize, isHalfWindow: false)
        let carryLength = max(settings.fftSize - settings.hopSize, 0)

        var channelStates = (0..<channelCount).map { index in
            ChannelState(label: layout.labels[safe: index] ?? "Ch\(index + 1)")
        }

        var totalReadFrames = 0

        while totalReadFrames < totalFrames {
            try Task.checkCancellation()

            let framesToRead = min(blockFrames, totalFrames - totalReadFrames)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(max(framesToRead, 1))
            ) else {
                throw AudioHapticError.invalidAnalysis("无法创建音频 buffer")
            }

            try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
            let readFrames = Int(buffer.frameLength)
            guard readFrames > 0 else {
                break
            }

            let channels = try extractFloatChannels(from: buffer, channelCount: channelCount)

            for channelIndex in 0..<channelCount {
                let existingCarry = channelStates[channelIndex].carry
                let segmentStart = totalReadFrames - existingCarry.count
                let segment = existingCarry + channels[channelIndex]

                processChannelSegment(
                    segment,
                    channelIndex: channelIndex,
                    segmentStartFrame: segmentStart,
                    sampleRate: sampleRate,
                    settings: settings,
                    hannWindow: hannWindow,
                    fftSetup: fftSetup,
                    log2n: log2n,
                    state: &channelStates[channelIndex]
                )

                channelStates[channelIndex].carry = carryLength > 0 ? Array(segment.suffix(carryLength)) : []
            }

            totalReadFrames += readFrames
            progress(min(1.0, Double(totalReadFrames) / Double(totalFrames)))
        }

        progress(1.0)

        let globalMaxRMS = max(
            channelStates
                .flatMap { $0.frames }
                .map(\.rms)
                .max() ?? 0,
            0.000001
        )

        let channels = channelStates.map { state in
            let marked = markTransients(frames: state.frames, cooldown: settings.transientCooldown)
            let maxFlux = max(marked.map(\.rawFlux).max() ?? 0, 0.000001)

            let frames = marked.map { frame in
                ChannelFeatureFrame(
                    time: frame.time,
                    rms: clamp01(frame.rms / globalMaxRMS),
                    spectralCentroidNorm: clamp01(frame.centroidNorm),
                    transientStrength: clamp01(frame.rawFlux / maxFlux),
                    isTransient: frame.isTransient
                )
            }

            return ChannelAnalysisResult(label: state.label, frames: frames)
        }

        return MultiChannelAnalysisResult(
            duration: Double(totalFrames) / sampleRate,
            sampleRate: sampleRate,
            layout: layout,
            channels: channels
        )
    }

    private func processChannelSegment(
        _ segment: [Float],
        channelIndex: Int,
        segmentStartFrame: Int,
        sampleRate: Double,
        settings: AnalyzerSettings,
        hannWindow: [Float],
        fftSetup: FFTSetup,
        log2n: vDSP_Length,
        state: inout ChannelState
    ) {
        guard segment.count >= settings.fftSize else {
            return
        }

        var frameStart = 0
        while frameStart + settings.fftSize <= segment.count {
            let absoluteFrameStart = segmentStartFrame + frameStart
            if absoluteFrameStart < 0 {
                frameStart += settings.hopSize
                continue
            }

            let frameSlice = Array(segment[frameStart..<(frameStart + settings.fftSize)])
            let windowed = applyWindow(frameSlice, window: hannWindow)

            let rms = computeRMS(windowed)
            let magnitudes = computeMagnitudes(windowed, fftSetup: fftSetup, log2n: log2n)
            let flux = spectralFlux(current: magnitudes, previous: state.previousMagnitudes)
            let centroidHz = spectralCentroidHz(
                magnitudes: magnitudes,
                sampleRate: Float(sampleRate),
                fftSize: settings.fftSize,
                lastValid: state.lastValidCentroidHz
            )

            state.lastValidCentroidHz = centroidHz
            state.previousMagnitudes = magnitudes

            let nyquist = Float(sampleRate / 2)
            let centroidNorm = normalizeLogFrequency(centroidHz, nyquist: nyquist)
            let time = Double(absoluteFrameStart) / sampleRate

            state.frames.append(
                PendingFeatureFrame(
                    time: time,
                    rms: rms,
                    centroidNorm: centroidNorm,
                    rawFlux: flux,
                    isTransient: false
                )
            )

            frameStart += settings.hopSize
        }
    }

    private func applyWindow(_ frame: [Float], window: [Float]) -> [Float] {
        zip(frame, window).map(*)
    }

    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + ($1 * $1) }
        return sqrt(sum / Float(samples.count))
    }

    private func computeMagnitudes(_ samples: [Float], fftSetup: FFTSetup, log2n: vDSP_Length) -> [Float] {
        let halfCount = samples.count / 2
        var real = [Float](repeating: 0, count: halfCount)
        var imag = [Float](repeating: 0, count: halfCount)
        var magnitudes = [Float](repeating: 0, count: halfCount)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                samples.withUnsafeBufferPointer { sourcePtr in
                    sourcePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfCount) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfCount))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfCount))
            }
        }

        for index in magnitudes.indices {
            magnitudes[index] = sqrt(max(magnitudes[index], 0))
        }
        return magnitudes
    }

    private func spectralFlux(current: [Float], previous: [Float]?) -> Float {
        guard let previous else {
            return 0
        }

        let count = min(current.count, previous.count)
        guard count > 0 else {
            return 0
        }

        var flux: Float = 0
        for index in 0..<count {
            let delta = current[index] - previous[index]
            if delta > 0 {
                flux += delta
            }
        }
        return flux
    }

    private func spectralCentroidHz(
        magnitudes: [Float],
        sampleRate: Float,
        fftSize: Int,
        lastValid: Float
    ) -> Float {
        guard !magnitudes.isEmpty else {
            return lastValid > 0 ? lastValid : sampleRate * 0.25
        }

        let binHz = sampleRate / Float(fftSize)
        var numerator: Float = 0
        var denominator: Float = 0

        for (index, value) in magnitudes.enumerated() {
            let frequency = Float(index) * binHz
            numerator += frequency * value
            denominator += value
        }

        guard denominator > 0.000001 else {
            return lastValid > 0 ? lastValid : sampleRate * 0.25
        }

        return numerator / denominator
    }

    private func normalizeLogFrequency(_ hz: Float, nyquist: Float) -> Float {
        guard nyquist > 0 else { return 0.5 }
        let safeHz = max(0, min(hz, nyquist))
        let numerator = log10(1 + safeHz)
        let denominator = log10(1 + nyquist)
        guard denominator > 0 else { return 0.5 }
        return numerator / denominator
    }

    private func markTransients(
        frames: [PendingFeatureFrame],
        cooldown: TimeInterval
    ) -> [PendingFeatureFrame] {
        guard !frames.isEmpty else { return [] }

        let fluxValues = frames.map(\.rawFlux)
        let mean = fluxValues.reduce(0, +) / Float(fluxValues.count)
        let variance = fluxValues.reduce(Float(0)) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Float(fluxValues.count)
        let std = sqrt(max(variance, 0))
        let threshold = mean + (0.5 * std)

        var mutable = frames
        var pendingIndex: Int?

        for index in mutable.indices {
            let frame = mutable[index]
            guard frame.rawFlux >= threshold else {
                continue
            }

            if let pending = pendingIndex {
                let delta = frame.time - mutable[pending].time
                if delta <= cooldown {
                    if frame.rawFlux > mutable[pending].rawFlux {
                        pendingIndex = index
                    }
                } else {
                    mutable[pending].isTransient = true
                    pendingIndex = index
                }
            } else {
                pendingIndex = index
            }
        }

        if let pendingIndex {
            mutable[pendingIndex].isTransient = true
        }

        return mutable
    }

    private func extractFloatChannels(from buffer: AVAudioPCMBuffer, channelCount: Int) throws -> [[Float]] {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else {
            return Array(repeating: [], count: channelCount)
        }

        if let floatData = buffer.floatChannelData {
            if buffer.format.isInterleaved {
                let interleaved = UnsafeBufferPointer(start: floatData[0], count: frames * channelCount)
                return strideInterleaved(interleaved: Array(interleaved), channels: channelCount, frames: frames)
            }
            return (0..<channelCount).map { channel in
                let pointer = UnsafeBufferPointer(start: floatData[channel], count: frames)
                return Array(pointer)
            }
        }

        if let int16Data = buffer.int16ChannelData {
            let scale = 1.0 / Float(Int16.max)
            if buffer.format.isInterleaved {
                let interleaved = UnsafeBufferPointer(start: int16Data[0], count: frames * channelCount)
                let converted = interleaved.map { Float($0) * scale }
                return strideInterleaved(interleaved: converted, channels: channelCount, frames: frames)
            }
            return (0..<channelCount).map { channel in
                let pointer = UnsafeBufferPointer(start: int16Data[channel], count: frames)
                return pointer.map { Float($0) * scale }
            }
        }

        if let int32Data = buffer.int32ChannelData {
            let scale = 1.0 / Float(Int32.max)
            if buffer.format.isInterleaved {
                let interleaved = UnsafeBufferPointer(start: int32Data[0], count: frames * channelCount)
                let converted = interleaved.map { Float($0) * scale }
                return strideInterleaved(interleaved: converted, channels: channelCount, frames: frames)
            }
            return (0..<channelCount).map { channel in
                let pointer = UnsafeBufferPointer(start: int32Data[channel], count: frames)
                return pointer.map { Float($0) * scale }
            }
        }

        throw AudioHapticError.invalidAudioFormat
    }

    private func strideInterleaved(interleaved: [Float], channels: Int, frames: Int) -> [[Float]] {
        var output = Array(repeating: Array(repeating: Float(0), count: frames), count: channels)
        for frame in 0..<frames {
            for channel in 0..<channels {
                output[channel][frame] = interleaved[(frame * channels) + channel]
            }
        }
        return output
    }

    private func clamp01(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}

private struct PendingFeatureFrame: Sendable {
    let time: TimeInterval
    let rms: Float
    let centroidNorm: Float
    let rawFlux: Float
    var isTransient: Bool
}

private struct ChannelState: Sendable {
    let label: String
    var frames: [PendingFeatureFrame] = []
    var carry: [Float] = []
    var previousMagnitudes: [Float]?
    var lastValidCentroidHz: Float = 0
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
