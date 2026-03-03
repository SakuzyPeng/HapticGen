import Foundation
import AVFoundation
import ZIPFoundation

/// 将本地 AHAP + 音频文件打包为带触觉旁路轨的 HLS 清单，并压缩为 zip 包（store-only）
///
/// zip 包内结构：
/// ```
/// haptic_trailer_<timestamp>.zip
///   ├── manifest.m3u8   ← 相对路径引用，跨设备有效
///   ├── <audioFileName>
///   └── <ahapFileName>
/// ```
public struct HLSPackager: Sendable {
    public init() {}

    /// 打包 Haptic Trailer 为 zip 包
    /// - Parameters:
    ///   - audioURL: 本地音频文件（file://）
    ///   - ahapURL:  本地 AHAP 文件（file://）
    /// - Returns: 写入临时目录的 .zip 文件 URL
    public func package(audioURL: URL, ahapURL: URL) throws -> URL {
        let duration = audioDuration(at: audioURL)
        let fm = FileManager.default
        let timestamp = Int(Date().timeIntervalSince1970)

        // 工作目录：把三个文件组装在一起
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("haptic_staging_\(timestamp)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let audioName = audioURL.lastPathComponent
        let ahapName  = ahapURL.lastPathComponent

        try fm.copyItem(at: audioURL, to: workDir.appendingPathComponent(audioName))
        try fm.copyItem(at: ahapURL,  to: workDir.appendingPathComponent(ahapName))

        // m3u8 使用相对路径，跨设备解压后仍然有效
        let manifest = """
            #EXTM3U
            #EXT-X-VERSION:3
            #EXT-X-SESSION-DATA:DATA-ID="com.apple.hls.haptics.url",VALUE="\(ahapName)"
            #EXT-X-TARGETDURATION:\(Int(duration.rounded(.up)))
            #EXT-X-MEDIA-SEQUENCE:0
            #EXTINF:\(String(format: "%.3f", duration)),
            \(audioName)
            #EXT-X-ENDLIST
            """
        guard let data = manifest.data(using: .utf8) else {
            throw AudioHapticError.exportFailed(L10n.Key.errorDetailManifestEncodingFailed)
        }
        try data.write(to: workDir.appendingPathComponent("manifest.m3u8"), options: .atomic)

        // store-only zip（不压缩，音频已压缩，二次压缩无意义）
        let zipURL = fm.temporaryDirectory
            .appendingPathComponent("haptic_trailer_\(timestamp).zip")
        try fm.zipItem(
            at: workDir,
            to: zipURL,
            shouldKeepParent: false,
            compressionMethod: .none
        )

        return zipURL
    }

    private func audioDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
