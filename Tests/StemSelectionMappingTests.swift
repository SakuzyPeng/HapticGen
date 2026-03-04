import XCTest
@testable import HapticGen

final class StemSelectionMappingTests: XCTestCase {

    // MARK: - StemKind 基础

    func testDefaultStemIsDrums() {
        XCTAssertEqual(StemKind.default, .drums)
    }

    func testAllCasesContainFiveStems() {
        XCTAssertEqual(StemKind.allCases.count, 5)
    }

    func testRawValuesAreCorrect() {
        XCTAssertEqual(StemKind.vocals.rawValue, "vocals")
        XCTAssertEqual(StemKind.piano.rawValue, "piano")
        XCTAssertEqual(StemKind.drums.rawValue, "drums")
        XCTAssertEqual(StemKind.bass.rawValue, "bass")
        XCTAssertEqual(StemKind.other.rawValue, "other")
    }

    func testFileBaseNameMatchesRawValue() {
        for stem in StemKind.allCases {
            XCTAssertEqual(stem.fileBaseName, stem.rawValue)
        }
    }

    // MARK: - StemSeparationArtifacts URL 映射

    func testArtifactsURLMappingForEachStem() {
        let workspace = URL(filePath: "/tmp/ws")
        let artifacts = StemSeparationArtifacts(
            workspaceDirectoryURL: workspace,
            processedStereo44kURL: workspace.appendingPathComponent("processed.wav"),
            vocalsURL: workspace.appendingPathComponent("vocals.wav"),
            pianoURL:  workspace.appendingPathComponent("piano.wav"),
            drumsURL:  workspace.appendingPathComponent("drums.wav"),
            bassURL:   workspace.appendingPathComponent("bass.wav"),
            otherURL:  workspace.appendingPathComponent("other.wav"),
            sourceOriginalURL: URL(filePath: "/tmp/source.wav")
        )

        XCTAssertEqual(artifacts.url(for: .vocals).lastPathComponent, "vocals.wav")
        XCTAssertEqual(artifacts.url(for: .piano).lastPathComponent,  "piano.wav")
        XCTAssertEqual(artifacts.url(for: .drums).lastPathComponent,  "drums.wav")
        XCTAssertEqual(artifacts.url(for: .bass).lastPathComponent,   "bass.wav")
        XCTAssertEqual(artifacts.url(for: .other).lastPathComponent,  "other.wav")
    }

    func testArtifactsURLsMustBeDistinct() {
        let workspace = URL(filePath: "/tmp/ws")
        let artifacts = StemSeparationArtifacts(
            workspaceDirectoryURL: workspace,
            processedStereo44kURL: workspace.appendingPathComponent("processed.wav"),
            vocalsURL: workspace.appendingPathComponent("vocals.wav"),
            pianoURL:  workspace.appendingPathComponent("piano.wav"),
            drumsURL:  workspace.appendingPathComponent("drums.wav"),
            bassURL:   workspace.appendingPathComponent("bass.wav"),
            otherURL:  workspace.appendingPathComponent("other.wav"),
            sourceOriginalURL: URL(filePath: "/tmp/source.wav")
        )

        let urls = StemKind.allCases.map { artifacts.url(for: $0) }
        let unique = Set(urls.map(\.lastPathComponent))
        XCTAssertEqual(unique.count, StemKind.allCases.count, "每个 stem 应有唯一 URL")
    }
}
