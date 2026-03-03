import XCTest
import AVFoundation
@testable import AudioHapticGenerator

/// 分析性能基准测试
///
/// 两个维度：
/// 1. 真实 8ch FLAC（aduio/8ch样本.flac）— 反映真实工作负载
/// 2. 合成 8ch WAV 60s @ 48kHz — 可复现的对照组
///
/// 每个 case 跑 3 次，输出 min / avg / max 和实时倍率（RTF）。
/// RTF = 音频时长 / 分析耗时，值越高代表越快。
final class AnalysisBenchmarkTests: XCTestCase {

    // MARK: - 真实 FLAC 基准

    func testBenchmark_Real8chFLAC() async throws {
        let flacURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("aduio/8ch样本.flac")

        guard FileManager.default.fileExists(atPath: flacURL.path) else {
            throw XCTSkip("真实样本不存在，跳过: \(flacURL.path)")
        }

        let audioDuration = try measureAudioDuration(at: flacURL)
        print("[Benchmark] 真实 FLAC: \(flacURL.lastPathComponent)  时长: \(String(format: "%.1f", audioDuration))s  声道: 8ch")

        await runBenchmark(url: flacURL, label: "真实8chFLAC", audioDuration: audioDuration, iterations: 3)
    }

    // MARK: - 合成音频基准（可复现）

    func testBenchmark_Synthetic8ch_60s() async throws {
        let url = try TestAudioFactory.makeMultichannelWAV(channelCount: 8, duration: 60.0, sampleRate: 48_000)
        print("[Benchmark] 合成 WAV: 8ch  60s  48kHz")
        await runBenchmark(url: url, label: "合成8ch_60s", audioDuration: 60.0, iterations: 3)
    }

    func testBenchmark_Synthetic2ch_60s() async throws {
        let url = try TestAudioFactory.makeMultichannelWAV(channelCount: 2, duration: 60.0, sampleRate: 48_000)
        print("[Benchmark] 合成 WAV: 2ch  60s  48kHz")
        await runBenchmark(url: url, label: "合成2ch_60s", audioDuration: 60.0, iterations: 3)
    }

    // MARK: - Core

    private func runBenchmark(
        url: URL,
        label: String,
        audioDuration: TimeInterval,
        iterations: Int
    ) async {
        let analyzer = AudioAnalyzer()
        var times: [TimeInterval] = []

        for i in 1...iterations {
            let start = Date()
            do {
                let result = try await analyzer.analyze(url: url)
                let elapsed = -start.timeIntervalSinceNow
                times.append(elapsed)
                let rtf = audioDuration / elapsed
                print(String(format: "[Benchmark] \(label)  #\(i)  elapsed=%.2fs  RTF=%.1f×  (%dch, %d frames/ch)",
                              elapsed, rtf,
                              result.channels.count,
                              result.channels.first?.frames.count ?? 0))
            } catch {
                XCTFail("[\(label)] #\(i) 分析失败: \(error.localizedDescription)")
                return
            }
        }

        guard !times.isEmpty else { return }
        let minT = times.min()!
        let maxT = times.max()!
        let avgT = times.reduce(0, +) / Double(times.count)

        print(String(format: "[Benchmark] \(label)  SUMMARY  min=%.2fs  avg=%.2fs  max=%.2fs  avgRTF=%.1f×",
                      minT, avgT, maxT, audioDuration / avgT))
        print("[Benchmark] ────────────────────────────────────────────────────")
    }

    private func measureAudioDuration(at url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
