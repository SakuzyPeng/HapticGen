import XCTest
@testable import HapticGen

final class TimeRegionMappingTests: XCTestCase {
    private func makeBinaural() -> ChannelMapping {
        ChannelMapping.defaults(for: ChannelLayout.detect(channelCount: 2))
    }

    private func makeCustom(lfe weight: Float) -> ChannelMapping {
        ChannelMapping(
            intensity: [ChannelWeight(channelLabel: "LFE", weight: weight)],
            sharpness: [],
            transient: []
        )
    }

    // MARK: - mapping(at:)

    func testDefaultMappingReturnedWhenNoRegions() {
        let base = makeBinaural()
        let regionMapping = TimeRegionMapping(defaultMapping: base)
        XCTAssertEqual(regionMapping.mapping(at: 0), base)
        XCTAssertEqual(regionMapping.mapping(at: 5), base)
    }

    func testRegionMappingReturnedWhenInsideRegion() {
        let base = makeBinaural()
        let custom = makeCustom(lfe: 1.0)
        let region = WeightRegion(startTime: 2, endTime: 5, mapping: custom)
        let regionMapping = TimeRegionMapping(defaultMapping: base, regions: [region])

        XCTAssertEqual(regionMapping.mapping(at: 2), custom)
        XCTAssertEqual(regionMapping.mapping(at: 3), custom)
        XCTAssertEqual(regionMapping.mapping(at: 4.999), custom)
    }

    func testDefaultReturnedOutsideRegion() {
        let base = makeBinaural()
        let custom = makeCustom(lfe: 1.0)
        let region = WeightRegion(startTime: 2, endTime: 5, mapping: custom)
        let regionMapping = TimeRegionMapping(defaultMapping: base, regions: [region])

        XCTAssertEqual(regionMapping.mapping(at: 0), base)
        XCTAssertEqual(regionMapping.mapping(at: 1.999), base)
        XCTAssertEqual(regionMapping.mapping(at: 5), base)    // endTime は含まない
        XCTAssertEqual(regionMapping.mapping(at: 10), base)
    }

    func testMultipleNonOverlappingRegions() {
        let base = makeBinaural()
        let r1 = WeightRegion(startTime: 0, endTime: 3, mapping: makeCustom(lfe: 0.5))
        let r2 = WeightRegion(startTime: 5, endTime: 8, mapping: makeCustom(lfe: 1.0))
        let regionMapping = TimeRegionMapping(defaultMapping: base, regions: [r1, r2])

        XCTAssertEqual(regionMapping.mapping(at: 1), r1.mapping)
        XCTAssertEqual(regionMapping.mapping(at: 4), base)  // gap between regions
        XCTAssertEqual(regionMapping.mapping(at: 6), r2.mapping)
    }

    // MARK: - addRegion(_:)

    func testAddRegionNoOverlap() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        let r = WeightRegion(startTime: 1, endTime: 3, mapping: makeCustom(lfe: 0.5))
        regionMapping.addRegion(r)

        XCTAssertEqual(regionMapping.regions.count, 1)
        XCTAssertEqual(regionMapping.regions[0].startTime, 1)
        XCTAssertEqual(regionMapping.regions[0].endTime, 3)
    }

    func testAddRegionTrimsExistingOnLeft() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        regionMapping.addRegion(WeightRegion(startTime: 0, endTime: 5, mapping: makeCustom(lfe: 0.5)))
        regionMapping.addRegion(WeightRegion(startTime: 3, endTime: 8, mapping: makeCustom(lfe: 1.0)))

        XCTAssertEqual(regionMapping.regions.count, 2)
        XCTAssertEqual(regionMapping.regions[0].endTime, 3, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[1].startTime, 3, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[1].endTime, 8, accuracy: 0.001)
    }

    func testAddRegionTrimsExistingOnRight() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        regionMapping.addRegion(WeightRegion(startTime: 5, endTime: 10, mapping: makeCustom(lfe: 0.5)))
        regionMapping.addRegion(WeightRegion(startTime: 2, endTime: 7, mapping: makeCustom(lfe: 1.0)))

        XCTAssertEqual(regionMapping.regions.count, 2)
        XCTAssertEqual(regionMapping.regions[0].endTime, 7, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[1].startTime, 7, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[1].endTime, 10, accuracy: 0.001)
    }

    func testAddRegionSplitsContainedRegion() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        regionMapping.addRegion(WeightRegion(startTime: 0, endTime: 10, mapping: makeCustom(lfe: 0.5)))
        regionMapping.addRegion(WeightRegion(startTime: 3, endTime: 7, mapping: makeCustom(lfe: 1.0)))

        XCTAssertEqual(regionMapping.regions.count, 3)
        XCTAssertEqual(regionMapping.regions[0].endTime, 3, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[1].startTime, 3, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[1].endTime, 7, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[2].startTime, 7, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[2].endTime, 10, accuracy: 0.001)
    }

    func testAddRegionFullOverwriteRemovesOldRegion() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        regionMapping.addRegion(WeightRegion(startTime: 2, endTime: 4, mapping: makeCustom(lfe: 0.5)))
        regionMapping.addRegion(WeightRegion(startTime: 0, endTime: 10, mapping: makeCustom(lfe: 1.0)))

        XCTAssertEqual(regionMapping.regions.count, 1)
        XCTAssertEqual(regionMapping.regions[0].startTime, 0)
        XCTAssertEqual(regionMapping.regions[0].endTime, 10)
    }

    // MARK: - removeRegion(id:)

    func testRemoveRegionById() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        let r1 = WeightRegion(startTime: 0, endTime: 3, mapping: makeCustom(lfe: 0.5))
        let r2 = WeightRegion(startTime: 5, endTime: 8, mapping: makeCustom(lfe: 1.0))
        regionMapping.addRegion(r1)
        regionMapping.addRegion(r2)
        regionMapping.removeRegion(id: r1.id)

        XCTAssertEqual(regionMapping.regions.count, 1)
        XCTAssertEqual(regionMapping.regions[0].id, r2.id)
    }

    // MARK: - resizeRegion

    func testResizeRegionStart() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        let r = WeightRegion(startTime: 2, endTime: 6, mapping: makeCustom(lfe: 1.0))
        regionMapping.addRegion(r)
        regionMapping.resizeRegion(id: r.id, newStart: 3, newEnd: nil)

        XCTAssertEqual(regionMapping.regions[0].startTime, 3, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[0].endTime, 6, accuracy: 0.001)
    }

    func testResizeRegionEnd() {
        let base = makeBinaural()
        var regionMapping = TimeRegionMapping(defaultMapping: base)
        let r = WeightRegion(startTime: 2, endTime: 6, mapping: makeCustom(lfe: 1.0))
        regionMapping.addRegion(r)
        regionMapping.resizeRegion(id: r.id, newStart: nil, newEnd: 8)

        XCTAssertEqual(regionMapping.regions[0].startTime, 2, accuracy: 0.001)
        XCTAssertEqual(regionMapping.regions[0].endTime, 8, accuracy: 0.001)
    }
}
