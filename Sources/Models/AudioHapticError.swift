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
            return L10n.errorInvalidAudioFormat
        case .unsupportedHaptics:
            return L10n.errorUnsupportedHaptics
        case .invalidAnalysis(let detail):
            return L10n.errorAnalysisFailed(detail: detail)
        case .generationFailed(let detail):
            return L10n.errorGenerationFailed(detail: detail)
        case .exportFailed(let detail):
            return L10n.errorExportFailed(detail: detail)
        case .playbackFailed(let detail):
            return L10n.errorPlaybackFailed(detail: detail)
        }
    }
}
