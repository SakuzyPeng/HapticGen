import Foundation
import AVFoundation
import Spleeter

/// 基于 swift-spleeter AudioSeparator5 的 5-stem 分离实现
final class Spleeter5StemSeparator: StemSeparating, @unchecked Sendable {

    private let modelURL: URL?
    private let preprocessor: AudioPreprocessing

    /// - Parameters:
    ///   - modelURL: 可选，指定 Spleeter5Model.mlmodelc 路径；nil 时从 Bundle.main 加载
    ///   - preprocessor: 音频预处理器，默认使用 AudioDownmixConverter
    init(modelURL: URL? = nil, preprocessor: AudioPreprocessing = AudioDownmixConverter()) {
        self.modelURL = modelURL ?? Bundle.main.url(forResource: "Spleeter5Model", withExtension: "mlmodelc")
        self.preprocessor = preprocessor
    }

    func separate(
        inputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> StemSeparationArtifacts {
        guard let modelURL else {
            throw AudioHapticError.separationFailed(L10n.Key.errorDetailModelNotFound)
        }

        // 1. 创建独立工作目录（每次分离使用独立 UUID 目录，避免文件冲突）
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("HapticGenStem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        do {
            // 2. 预处理：下混 + 重采样至 stereo 44.1kHz
            let processedURL = workspace.appendingPathComponent("processed.wav")
            try preprocessor.makeStereo44100(inputURL: inputURL, outputURL: processedURL)

            // 3. 构建输出 URL（Stems5<URL>）
            let stemURLs = Stems5<URL>(
                vocals: workspace.appendingPathComponent("vocals.wav"),
                piano:  workspace.appendingPathComponent("piano.wav"),
                drums:  workspace.appendingPathComponent("drums.wav"),
                bass:   workspace.appendingPathComponent("bass.wav"),
                other:  workspace.appendingPathComponent("other.wav")
            )

            // 4. 初始化 AudioSeparator5 并运行分离
            let separator = try AudioSeparator5(modelURL: modelURL)
            for try await p in separator.separate(from: processedURL, to: stemURLs) {
                progress(Double(p.fraction))
            }
            progress(1.0)

            return StemSeparationArtifacts(
                workspaceDirectoryURL: workspace,
                processedStereo44kURL: processedURL,
                vocalsURL: stemURLs.vocals,
                pianoURL:  stemURLs.piano,
                drumsURL:  stemURLs.drums,
                bassURL:   stemURLs.bass,
                otherURL:  stemURLs.other,
                sourceOriginalURL: inputURL
            )
        } catch {
            // 分离失败时清理工作目录
            try? FileManager.default.removeItem(at: workspace)
            if let hapticError = error as? AudioHapticError {
                throw hapticError
            }
            throw AudioHapticError.separationFailed(error.localizedDescription)
        }
    }
}
