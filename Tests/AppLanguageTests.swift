import XCTest
@testable import AudioHapticGenerator

final class AppLanguageTests: XCTestCase {
    func testResolvedFallsBackToAuto() {
        XCTAssertEqual(AppLanguage.resolved(rawValue: nil), .auto)
        XCTAssertEqual(AppLanguage.resolved(rawValue: "invalid"), .auto)
    }

    func testLocaleMapping() {
        XCTAssertEqual(AppLanguage.auto.rawValue, "auto")
        XCTAssertEqual(AppLanguage.zhHans.locale.identifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.en.locale.identifier, "en")
        XCTAssertFalse(AppLanguage.auto.locale.identifier.isEmpty)
    }
}
