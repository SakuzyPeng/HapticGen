import Foundation

public enum ChannelLayoutType: Equatable, Sendable {
    case binaural2
    case surround71_8
    case atmos714_12
    case atmos916_16
    case cicp13_222_24
    case custom(Int)
}

public struct ChannelLayout: Equatable, Sendable {
    public let type: ChannelLayoutType
    public let channelCount: Int
    public let labels: [String]

    public init(type: ChannelLayoutType, channelCount: Int, labels: [String]) {
        self.type = type
        self.channelCount = channelCount
        self.labels = labels
    }

    public static func detect(channelCount: Int) -> ChannelLayout {
        switch channelCount {
        case 2:
            return ChannelLayout(type: .binaural2, channelCount: 2, labels: ["L", "R"])
        case 8:
            return ChannelLayout(
                type: .surround71_8,
                channelCount: 8,
                labels: ["L", "R", "C", "LFE", "Rls", "Rrs", "Ls", "Rs"]
            )
        case 12:
            return ChannelLayout(
                type: .atmos714_12,
                channelCount: 12,
                labels: ["L", "R", "C", "LFE", "Rls", "Rrs", "Ls", "Rs", "Vhl", "Vhr", "Ltr", "Rtr"]
            )
        case 16:
            return ChannelLayout(
                type: .atmos916_16,
                channelCount: 16,
                labels: ["L", "R", "C", "LFE", "Rls", "Rrs", "Ls", "Rs", "Vhl", "Vhr", "Ltr", "Rtr", "Lw", "Rw", "Ltm", "Rtm"]
            )
        case 24:
            return ChannelLayout(
                type: .cicp13_222_24,
                channelCount: 24,
                labels: [
                    "L", "R", "C", "LFE1", "LFE2", "Ls", "Rs", "Lrs", "Rrs", "Ltf", "Rtf", "Ltm",
                    "Rtm", "Ltr", "Rtr", "Ltb", "Rtb", "Lw", "Rw", "Lv", "Rv", "Cv", "Ch", "Oh"
                ]
            )
        default:
            return ChannelLayout(
                type: .custom(channelCount),
                channelCount: channelCount,
                labels: (1...max(channelCount, 0)).map { "Ch\($0)" }
            )
        }
    }
}
