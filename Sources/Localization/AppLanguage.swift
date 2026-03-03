import Foundation

public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case auto
    case zhHans
    case en

    public static let storageKey = "app.language.override"

    public var id: String { rawValue }

    public var locale: Locale {
        switch self {
        case .auto:
            return .autoupdatingCurrent
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .en:
            return Locale(identifier: "en")
        }
    }

    var localizationIdentifier: String? {
        switch self {
        case .auto:
            return nil
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    public static func resolved(rawValue: String?) -> AppLanguage {
        guard let rawValue else {
            return .auto
        }
        return AppLanguage(rawValue: rawValue) ?? .auto
    }

    public static var persisted: AppLanguage {
        resolved(rawValue: UserDefaults.standard.string(forKey: storageKey))
    }
}
