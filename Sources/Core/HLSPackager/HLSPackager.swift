import Foundation
import AVFoundation

/// 将本地 AHAP + 音频文件打包为带触觉旁路轨的 HLS 清单（.m3u8）
///
/// 生成的清单完全基于本地 file:// URL，无需 HTTP 服务器。
/// VALUE 字段遵循 Apple TV App 所用的 com.apple.hls.haptics.url 约定。
public struct HLSPackager: Sendable {
    public init() {}

    /// 打包 Haptic Trailer 清单
    /// - Parameters:
    ///   - audioURL: 本地音频文件（file://）
    ///   - ahapURL:  本地 AHAP 文件（file://）
    /// - Returns: 写入临时目录的 .m3u8 清单 URL
    public func package(audioURL: URL, ahapURL: URL) throws -> URL {
        let duration = audioDuration(at: audioURL)

        let manifest = """
            #EXTM3U
            #EXT-X-VERSION:3
            #EXT-X-SESSION-DATA:DATA-ID="com.apple.hls.haptics.url",VALUE="\(ahapURL.absoluteString)"
            #EXT-X-TARGETDURATION:\(Int(duration.rounded(.up)))
            #EXT-X-MEDIA-SEQUENCE:0
            #EXTINF:\(String(format: "%.3f", duration)),
            \(audioURL.absoluteString)
            #EXT-X-ENDLIST
            """

        let timestamp = Int(Date().timeIntervalSince1970)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haptic_trailer_\(timestamp)")
            .appendingPathExtension("m3u8")

        guard let data = manifest.data(using: .utf8) else {
            throw AudioHapticError.exportFailed("清单编码失败")
        }

        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private func audioDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
