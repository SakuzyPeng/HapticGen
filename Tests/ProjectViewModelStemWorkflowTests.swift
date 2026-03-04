import XCTest
@testable import HapticGen

// MARK: - Mock

/// 总是成功的 mock 分离器，立即返回预设的 artifacts
actor MockStemSeparator: StemSeparating {

    private let workspace: URL
    let artifacts: StemSeparationArtifacts

    init() {
        let ws = FileManager.default.temporaryDirectory
            .appendingPathComponent("MockStemSep-\(UUID().uuidString)")
        self.workspace = ws
        self.artifacts = StemSeparationArtifacts(
            workspaceDirectoryURL: ws,
            processedStereo44kURL: ws.appendingPathComponent("processed.wav"),
            vocalsURL: ws.appendingPathComponent("vocals.wav"),
            pianoURL:  ws.appendingPathComponent("piano.wav"),
            drumsURL:  ws.appendingPathComponent("drums.wav"),
            bassURL:   ws.appendingPathComponent("bass.wav"),
            otherURL:  ws.appendingPathComponent("other.wav"),
            sourceOriginalURL: URL(filePath: "/dev/null")
        )
    }

    func separate(
        inputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> StemSeparationArtifacts {
        progress(1.0)
        return artifacts
    }
}

/// 总是失败的 mock 分离器
struct FailingStemSeparator: StemSeparating {
    func separate(inputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> StemSeparationArtifacts {
        throw AudioHapticError.separationFailed("Mock failure")
    }
}

// MARK: - Tests

@MainActor
final class ProjectViewModelStemWorkflowTests: XCTestCase {

    // MARK: importAudio 后分离状态应清空

    func testImportAudioClearsSeparationState() throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)

        // 模拟已有 artifacts 状态
        let ws = URL(filePath: "/tmp/ws")
        let fakeArtifacts = StemSeparationArtifacts(
            workspaceDirectoryURL: ws,
            processedStereo44kURL: ws.appendingPathComponent("p.wav"),
            vocalsURL: ws.appendingPathComponent("v.wav"), pianoURL: ws.appendingPathComponent("pi.wav"),
            drumsURL:  ws.appendingPathComponent("d.wav"), bassURL:  ws.appendingPathComponent("b.wav"),
            otherURL:  ws.appendingPathComponent("o.wav"), sourceOriginalURL: URL(filePath: "/dev/null")
        )
        vm.separationArtifacts = fakeArtifacts

        // 导入一个临时文件（只需存在）
        let tmpAudio = try TestAudioFactory.makeStereoWAV(
            duration: 0.1, sampleRate: 44_100,
            left: { _, _ in 0 }, right: { _, _ in 0 }
        )
        vm.importAudio(url: tmpAudio)

        XCTAssertNil(vm.separationArtifacts, "importAudio 后 separationArtifacts 应为 nil")
        XCTAssertFalse(vm.isSeparating)
        XCTAssertEqual(vm.separationProgress, 0)
    }

    // MARK: separateStems 成功后状态正确

    func testSeparateStemsSuccessUpdatesState() async throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)

        // 需要一个 selectedAudioURL
        let tmpAudio = try TestAudioFactory.makeStereoWAV(
            duration: 0.1, sampleRate: 44_100,
            left: { _, _ in 0 }, right: { _, _ in 0 }
        )
        vm.importAudio(url: tmpAudio)

        vm.separateStems()

        // 等待异步任务完成
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.separationArtifacts, "分离成功后 separationArtifacts 应非 nil")
        XCTAssertFalse(vm.isSeparating, "分离完成后 isSeparating 应为 false")
        XCTAssertEqual(vm.separationProgress, 1.0, accuracy: 0.01)
    }

    // MARK: analyzeAudio 在未分离时应设置 errorMessage

    func testAnalyzeAudioWithoutSeparationSetsError() throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)

        vm.analyzeAudio()

        XCTAssertNotNil(vm.errorMessage, "未分离时 analyzeAudio 应设置 errorMessage")
    }

    // MARK: selectStem 切换后清空分析结果

    func testSelectStemClearsAnalysisState() throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)

        // 模拟已有分析结果
        let fakeAnalysis = MultiChannelAnalysisResult(
            duration: 1.0, sampleRate: 44100,
            layout: ChannelLayout.detect(channelCount: 1),
            channels: []
        )
        vm.analysisResult = fakeAnalysis
        vm.selectedStem = .drums

        vm.selectStem(.vocals)

        XCTAssertEqual(vm.selectedStem, .vocals)
        XCTAssertNil(vm.analysisResult, "切换 stem 后 analysisResult 应清空")
        XCTAssertNil(vm.patternDescriptor)
        XCTAssertNil(vm.generatedPattern)
    }

    // MARK: selectStem 切换到相同 stem 不清空

    func testSelectSameStemDoesNotClearState() throws {
        let mock = MockStemSeparator()
        let vm = ProjectViewModel(stemSeparator: mock)

        let fakeAnalysis = MultiChannelAnalysisResult(
            duration: 1.0, sampleRate: 44100,
            layout: ChannelLayout.detect(channelCount: 1),
            channels: []
        )
        vm.analysisResult = fakeAnalysis
        vm.selectedStem = .drums

        vm.selectStem(.drums)  // 相同 stem

        XCTAssertNotNil(vm.analysisResult, "选择相同 stem 不应清空分析结果")
    }

    // MARK: 分离失败时 errorMessage 应被设置

    func testSeparateStemsFailureSetsError() async throws {
        let vm = ProjectViewModel(stemSeparator: FailingStemSeparator())

        let tmpAudio = try TestAudioFactory.makeStereoWAV(
            duration: 0.1, sampleRate: 44_100,
            left: { _, _ in 0 }, right: { _, _ in 0 }
        )
        vm.importAudio(url: tmpAudio)
        vm.separateStems()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(vm.errorMessage, "分离失败后应设置 errorMessage")
        XCTAssertNil(vm.separationArtifacts, "分离失败后 artifacts 应为 nil")
        XCTAssertFalse(vm.isSeparating)
    }
}
