import Foundation

/// 5-stem 分离后产生的所有文件 URL 及工作目录信息
struct StemSeparationArtifacts: Sendable {
    /// 本次分离使用的临时工作目录（再次导入时由调用方删除）
    let workspaceDirectoryURL: URL
    /// 预处理后的 stereo 44.1kHz WAV（Spleeter 输入）
    let processedStereo44kURL: URL
    /// 5 个分离输出（单声道 WAV）
    let vocalsURL: URL
    let pianoURL: URL
    let drumsURL: URL
    let bassURL: URL
    let otherURL: URL
    /// 原始导入文件 URL
    let sourceOriginalURL: URL

    /// 根据 StemKind 返回对应的输出 WAV URL
    func url(for stem: StemKind) -> URL {
        switch stem {
        case .vocals: return vocalsURL
        case .piano:  return pianoURL
        case .drums:  return drumsURL
        case .bass:   return bassURL
        case .other:  return otherURL
        }
    }
}
