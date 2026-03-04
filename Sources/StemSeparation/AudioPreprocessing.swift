import Foundation

/// 音频预处理协议：将任意音频转换为 stereo 44.1kHz Float32 WAV
protocol AudioPreprocessing: Sendable {
    /// 将 inputURL 指向的音频下混并重采样，写入 outputURL，返回 outputURL
    @discardableResult
    func makeStereo44100(inputURL: URL, outputURL: URL) throws -> URL
}
