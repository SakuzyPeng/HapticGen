import Foundation

/// Spleeter 5-stem 分离的音轨种类
enum StemKind: String, CaseIterable, Sendable, Hashable {
    case vocals
    case piano
    case drums
    case bass
    case other

    static let `default`: StemKind = .drums

    var displayName: String { L10n.stemKindName(self) }

    var fileBaseName: String { rawValue }
}
