import Foundation

public enum AudioHapticError: LocalizedError {
    case invalidAudioFormat
    case unsupportedHaptics
    case invalidAnalysis(String)
    case generationFailed(String)
    case exportFailed(String)
    case playbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAudioFormat:
            return "无法解析音频格式。"
        case .unsupportedHaptics:
            return "当前设备不支持触觉功能。"
        case .invalidAnalysis(let detail):
            return "音频分析失败：\(detail)"
        case .generationFailed(let detail):
            return "触觉生成失败：\(detail)"
        case .exportFailed(let detail):
            return "导出失败：\(detail)"
        case .playbackFailed(let detail):
            return "播放失败：\(detail)"
        }
    }
}
