import XCTest
@testable import AudioHapticGenerator

final class L10nTests: XCTestCase {
    func testStatusFormattingContainsArguments() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.storageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppLanguage.storageKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.storageKey)
            }
        }

        defaults.set(AppLanguage.en.rawValue, forKey: AppLanguage.storageKey)
        let english = L10n.statusAnalysisCompleted(channelCount: 8)
        XCTAssertTrue(english.contains("8"))

        defaults.set(AppLanguage.zhHans.rawValue, forKey: AppLanguage.storageKey)
        let chinese = L10n.statusAnalysisCompleted(channelCount: 8)
        XCTAssertTrue(chinese.contains("8"))

        XCTAssertNotEqual(english, chinese)
    }

    func testErrorTemplateUsesLocalizedDetailKey() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppLanguage.storageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppLanguage.storageKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.storageKey)
            }
        }

        defaults.set(AppLanguage.en.rawValue, forKey: AppLanguage.storageKey)
        let message = L10n.errorPlaybackFailed(detail: L10n.Key.errorDetailPrepareFirst)

        XCTAssertFalse(message.contains(L10n.Key.errorDetailPrepareFirst))
        XCTAssertTrue(message.lowercased().contains("prepare"))
    }
}
