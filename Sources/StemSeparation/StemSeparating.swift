import Foundation

/// 5-stem 分离的抽象协议（便于测试时注入 mock 实现）
protocol StemSeparating: Sendable {
    /// 将输入音频分离为 5 个 stem，通过 progress 回调报告进度（0.0–1.0）
    func separate(
        inputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> StemSeparationArtifacts
}
