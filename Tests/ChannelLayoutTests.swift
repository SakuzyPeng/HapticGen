import XCTest
@testable import HapticGen

final class ChannelLayoutTests: XCTestCase {
    func testKnownLayouts() {
        XCTAssertEqual(ChannelLayout.detect(channelCount: 2).type, .binaural2)
        XCTAssertEqual(ChannelLayout.detect(channelCount: 8).type, .surround71_8)
        XCTAssertEqual(ChannelLayout.detect(channelCount: 12).type, .atmos714_12)
        XCTAssertEqual(ChannelLayout.detect(channelCount: 16).type, .atmos916_16)
        XCTAssertEqual(ChannelLayout.detect(channelCount: 24).type, .cicp13_222_24)
    }

    func testCustomLayoutLabels() {
        let layout = ChannelLayout.detect(channelCount: 5)
        XCTAssertEqual(layout.type, .custom(5))
        XCTAssertEqual(layout.labels, ["Ch1", "Ch2", "Ch3", "Ch4", "Ch5"])
    }
}
