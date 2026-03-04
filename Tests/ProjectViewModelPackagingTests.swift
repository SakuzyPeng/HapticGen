import XCTest
@testable import HapticGen

/// 验证 packageHapticTrailer / exportAHAP 使用的是选中 stem 的音频 URL，而非原始 URL
@MainActor
final class ProjectViewModelPackagingTests: XCTestCase {

    // MARK: - packageHapticTrailer 使用 stem 音频

    func testPackageTrailerUsesSelectedStemAudio() async throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)

        // 导入并分离
        let tmpAudio = try TestAudioFactory.makeStereoWAV(
            duration: 0.1, sampleRate: 44_100,
            left: { _, _ in 0 }, right: { _, _ in 0 }
        )
        vm.importAudio(url: tmpAudio)
        vm.separateStems()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.separationArtifacts, "前提：分离应成功")

        // 验证 selectedStem 对应的 URL 与 artifacts.url(for:) 一致
        let expectedURL = vm.separationArtifacts!.url(for: vm.selectedStem)
        XCTAssertEqual(expectedURL.lastPathComponent, "\(vm.selectedStem.rawValue).wav",
                       "默认 stem 应为 \(StemKind.default.rawValue)")
    }

    // MARK: - exportAHAP 文件名包含 stem 后缀

    func testExportAHAPFileNameContainsStemSuffix() async throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)

        let tmpAudio = try TestAudioFactory.makeStereoWAV(
            duration: 0.1, sampleRate: 44_100,
            left: { _, _ in 0 }, right: { _, _ in 0 }
        )
        vm.importAudio(url: tmpAudio)
        vm.separateStems()
        try await Task.sleep(nanoseconds: 200_000_000)

        // 需要一个 patternDescriptor 才能导出
        // 因为没有真实分析，创建一个最小 descriptor
        vm.patternDescriptor = HapticPatternDescriptor(
            duration: 0.1,
            continuousEvent: ContinuousEventDescriptor(duration: 0.1),
            intensityCurvePoints: [],
            sharpnessCurvePoints: [],
            transientEvents: []
        )
        vm.selectedStem = .bass

        vm.exportAHAP()

        // exportedAHAPPath 应包含 "_bass.ahap"
        XCTAssertTrue(vm.exportedAHAPPath.contains("_bass"),
                      "导出路径应包含 stem 后缀，实际：\(vm.exportedAHAPPath)")
        XCTAssertTrue(vm.exportedAHAPPath.hasSuffix(".ahap"))
    }

    // MARK: - 未分离时 packageHapticTrailer 应设置 errorMessage

    func testPackageTrailerWithoutSeparationSetsError() async throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)
        vm.patternDescriptor = HapticPatternDescriptor(
            duration: 0.1,
            continuousEvent: ContinuousEventDescriptor(duration: 0.1),
            intensityCurvePoints: [], sharpnessCurvePoints: [], transientEvents: []
        )

        await vm.packageHapticTrailer()

        XCTAssertNotNil(vm.errorMessage, "未分离时打包应报错")
    }
}
