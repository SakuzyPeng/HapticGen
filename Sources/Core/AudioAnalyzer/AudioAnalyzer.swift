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
        let carryLength = max(settings.fftSize - settings.hopSize, 0)

        let hannWindow = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: settings.fftSize,
            isHalfWindow: false
        )

        // 预计算频率 bin（整个分析过程恒定，避免每帧重建）
        let halfFFT = settings.fftSize / 2
        var binHzStep = Float(sampleRate) / Float(settings.fftSize)
        var freqBinStart: Float = 0
        var freqBins = [Float](repeating: 0, count: halfFFT)
        vDSP_vramp(&freqBinStart, &binHzStep, &freqBins, 1, vDSP_Length(halfFFT))
        let nyquist = Float(sampleRate / 2)

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
                throw AudioHapticError.invalidAnalysis(L10n.Key.errorDetailAudioBufferCreationFailed)
            }

            try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
            let readFrames = Int(buffer.frameLength)
            guard readFrames > 0 else { break }

            let channelData = try extractFloatChannels(from: buffer, channelCount: channelCount)

            // 所有声道并行处理（每个 task 独立的 FFTSetup，无共享状态）
            let capturedStates = channelStates
            let capturedTotal = totalReadFrames
            channelStates = try await withThrowingTaskGroup(of: (Int, ChannelState).self) { group in
                for channelIndex in 0..<channelCount {
                    let state = capturedStates[channelIndex]
                    let samples = channelData[channelIndex]
                    let segment = state.carry + samples
                    let segmentStart = capturedTotal - state.carry.count
                    let localHann = hannWindow
                    let localFreqBins = freqBins

                    group.addTask {
                        guard let localFFT = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
                            return (channelIndex, state)
                        }
                        defer { vDSP_destroy_fftsetup(localFFT) }

                        var localState = state
                        Self.processChannelSegment(
                            segment,
                            segmentStartFrame: segmentStart,
                            sampleRate: sampleRate,
                            settings: settings,
                            hannWindow: localHann,
                            freqBins: localFreqBins,
                            nyquist: nyquist,
                            fftSetup: localFFT,
                            log2n: log2n,
                            state: &localState
                        )
                        localState.carry = carryLength > 0 ? Array(segment.suffix(carryLength)) : []
                        return (channelIndex, localState)
                    }
                }

                var result = capturedStates
                for try await (index, state) in group {
                    result[index] = state
                }
                return result
            }

            totalReadFrames += readFrames
            progress(min(1.0, Double(totalReadFrames) / Double(totalFrames)))
        }

        progress(1.0)

        let globalMaxRMS = max(
            channelStates.flatMap { $0.frames }.map(\.rms).max() ?? 0,
            0.000001
        )

        let channels = channelStates.map { state in
            let marked = Self.markTransients(frames: state.frames, cooldown: settings.transientCooldown)
            let maxFlux = max(marked.map(\.rawFlux).max() ?? 0, 0.000001)

            let frames = marked.map { frame in
                ChannelFeatureFrame(
                    time: frame.time,
                    rms: Self.clamp01(frame.rms / globalMaxRMS),
                    spectralCentroidNorm: Self.clamp01(frame.centroidNorm),
                    transientStrength: Self.clamp01(frame.rawFlux / maxFlux),
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

    // MARK: - Channel Processing（static，供 @Sendable task 调用）

    private static func processChannelSegment(
        _ segment: [Float],
        segmentStartFrame: Int,
        sampleRate: Double,
        settings: AnalyzerSettings,
        hannWindow: [Float],
        freqBins: [Float],
        nyquist: Float,
        fftSetup: FFTSetup,
        log2n: vDSP_Length,
        state: inout ChannelState
    ) {
        guard segment.count >= settings.fftSize else { return }

        var frameStart = 0
        while frameStart + settings.fftSize <= segment.count {
            let absoluteFrameStart = segmentStartFrame + frameStart
            if absoluteFrameStart < 0 {
                frameStart += settings.hopSize
                continue
            }

            // 加窗：vDSP.multiply 替代 zip().map(*)
            let frameSlice = Array(segment[frameStart..<(frameStart + settings.fftSize)])
            let windowed = vDSP.multiply(frameSlice, hannWindow)

            let rms = computeRMS(windowed)
            let magnitudes = computeMagnitudes(windowed, fftSetup: fftSetup, log2n: log2n)
            let flux = spectralFlux(current: magnitudes, previous: state.previousMagnitudes)
            let centroidHz = spectralCentroid(
                magnitudes: magnitudes,
                freqBins: freqBins,
                lastValid: state.lastValidCentroidHz,
                nyquist: nyquist
            )

            state.lastValidCentroidHz = centroidHz
            state.previousMagnitudes = magnitudes

            state.frames.append(PendingFeatureFrame(
                time: Double(absoluteFrameStart) / sampleRate,
                rms: rms,
                centroidNorm: normalizeLogFrequency(centroidHz, nyquist: nyquist),
                rawFlux: flux,
                isTransient: false
            ))

            frameStart += settings.hopSize
        }
    }

    // MARK: - vDSP-accelerated Math

    /// RMS：vDSP_rmsqv 替代 reduce + sqrt
    private static func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }

    /// FFT + 幅值：vvsqrtf 替代逐元素 Swift sqrt 循环
    private static func computeMagnitudes(_ samples: [Float], fftSetup: FFTSetup, log2n: vDSP_Length) -> [Float] {
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

        // 向量化 sqrt（vvsqrtf）替代 for 循环
        var sqrtInput = magnitudes
        var count = Int32(halfCount)
        vvsqrtf(&magnitudes, &sqrtInput, &count)
        return magnitudes
    }

    /// Spectral Flux：vDSP 向量减法 + 阈值截断 + 求和，替代 Swift for 循环
    private static func spectralFlux(current: [Float], previous: [Float]?) -> Float {
        guard let previous else { return 0 }
        let count = min(current.count, previous.count)
        guard count > 0 else { return 0 }

        var diff = [Float](repeating: 0, count: count)
        // diff = current - previous（vDSP_vsub: C = B - A）
        vDSP_vsub(previous, 1, current, 1, &diff, 1, vDSP_Length(count))
        // 半波整流：将负值截为 0（独立输出 buffer 避免 exclusive access 冲突）
        var zero: Float = 0
        var rectified = [Float](repeating: 0, count: count)
        vDSP_vthres(diff, 1, &zero, &rectified, 1, vDSP_Length(count))
        var flux: Float = 0
        vDSP_sve(rectified, 1, &flux, vDSP_Length(count))
        return flux
    }

    /// 频谱重心：vDSP_dotpr + vDSP_sve + 预计算 freqBins，替代 Swift enumerated 循环
    private static func spectralCentroid(
        magnitudes: [Float],
        freqBins: [Float],
        lastValid: Float,
        nyquist: Float
    ) -> Float {
        guard !magnitudes.isEmpty else {
            return lastValid > 0 ? lastValid : nyquist * 0.25
        }

        var denominator: Float = 0
        vDSP_sve(magnitudes, 1, &denominator, vDSP_Length(magnitudes.count))

        guard denominator > 0.000001 else {
            return lastValid > 0 ? lastValid : nyquist * 0.25
        }

        var numerator: Float = 0
        let usedCount = min(freqBins.count, magnitudes.count)
        vDSP_dotpr(
            freqBins, 1,
            magnitudes, 1,
            &numerator,
            vDSP_Length(usedCount)
        )

        return numerator / denominator
    }

    private static func normalizeLogFrequency(_ hz: Float, nyquist: Float) -> Float {
        guard nyquist > 0 else { return 0.5 }
        let safeHz = max(0, min(hz, nyquist))
        let numerator = log10(1 + safeHz)
        let denominator = log10(1 + nyquist)
        guard denominator > 0 else { return 0.5 }
        return numerator / denominator
    }

    private static func markTransients(
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
        let threshold = mean + (0.5 * sqrt(max(variance, 0)))

        var mutable = frames
        var pendingIndex: Int?

        for index in mutable.indices {
            let frame = mutable[index]
            guard frame.rawFlux >= threshold else { continue }

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

    // MARK: - Audio Buffer Extraction

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
                Array(UnsafeBufferPointer(start: floatData[channel], count: frames))
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
                UnsafeBufferPointer(start: int16Data[channel], count: frames).map { Float($0) * scale }
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
                UnsafeBufferPointer(start: int32Data[channel], count: frames).map { Float($0) * scale }
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

    private static func clamp01(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}

// MARK: - Internal Types

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
