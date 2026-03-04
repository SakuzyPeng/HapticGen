import XCTest
@testable import HapticGen

final class EditableHapticPatternTests: XCTestCase {
    private func makeDescriptor() -> HapticPatternDescriptor {
        let intensityPts = [
            CurvePoint(time: 0.0, value: 0.2),
            CurvePoint(time: 0.5, value: 0.8),
            CurvePoint(time: 1.0, value: 0.4)
        ]
        let sharpnessPts = [
            CurvePoint(time: 0.0, value: 0.5),
            CurvePoint(time: 1.0, value: 0.7)
        ]
        let transients = [
            TransientPoint(time: 0.25, intensity: 0.9, sharpness: 0.6),
            TransientPoint(time: 0.75, intensity: 0.7, sharpness: 0.8)
        ]
        return HapticPatternDescriptor(
            duration: 1.0,
            continuousEvent: ContinuousEventDescriptor(duration: 1.0),
            intensityCurvePoints: intensityPts,
            sharpnessCurvePoints: sharpnessPts,
            transientEvents: transients
        )
    }

    // MARK: - init(from:)

    func testInitFromDescriptorPreservesPointCount() {
        let descriptor = makeDescriptor()
        let editable = EditableHapticPattern(from: descriptor)

        XCTAssertEqual(editable.intensityCurve.count, 3)
        XCTAssertEqual(editable.sharpnessCurve.count, 2)
        XCTAssertEqual(editable.transients.count, 2)
        XCTAssertEqual(editable.duration, 1.0)
    }

    func testInitFromDescriptorPreservesValues() {
        let descriptor = makeDescriptor()
        let editable = EditableHapticPattern(from: descriptor)

        XCTAssertEqual(editable.intensityCurve[0].time, 0.0, accuracy: 0.0001)
        XCTAssertEqual(editable.intensityCurve[0].value, 0.2, accuracy: 0.0001)
        XCTAssertEqual(editable.transients[0].intensity, 0.9, accuracy: 0.0001)
        XCTAssertEqual(editable.transients[0].sharpness, 0.6, accuracy: 0.0001)
    }

    func testInitAssignsUniqueIDs() {
        let descriptor = makeDescriptor()
        let editable = EditableHapticPattern(from: descriptor)

        let intensityIDs = Set(editable.intensityCurve.map(\.id))
        let transientIDs = Set(editable.transients.map(\.id))
        XCTAssertEqual(intensityIDs.count, 3)
        XCTAssertEqual(transientIDs.count, 2)
    }

    // MARK: - toDescriptor()

    func testRoundTripPreservesValues() {
        let original = makeDescriptor()
        let editable = EditableHapticPattern(from: original)
        let restored = editable.toDescriptor()

        XCTAssertEqual(restored.duration, original.duration, accuracy: 0.0001)
        XCTAssertEqual(restored.intensityCurvePoints.count, original.intensityCurvePoints.count)
        XCTAssertEqual(restored.sharpnessCurvePoints.count, original.sharpnessCurvePoints.count)
        XCTAssertEqual(restored.transientEvents.count, original.transientEvents.count)

        for (a, b) in zip(restored.intensityCurvePoints, original.intensityCurvePoints) {
            XCTAssertEqual(a.time, b.time, accuracy: 0.0001)
            XCTAssertEqual(a.value, b.value, accuracy: 0.0001)
        }
        for (a, b) in zip(restored.transientEvents, original.transientEvents) {
            XCTAssertEqual(a.time, b.time, accuracy: 0.0001)
            XCTAssertEqual(a.intensity, b.intensity, accuracy: 0.0001)
            XCTAssertEqual(a.sharpness, b.sharpness, accuracy: 0.0001)
        }
    }

    func testMutationReflectedInDescriptor() {
        let original = makeDescriptor()
        var editable = EditableHapticPattern(from: original)
        let id = editable.intensityCurve[1].id
        let idx = editable.intensityCurve.firstIndex(where: { $0.id == id })!
        editable.intensityCurve[idx].value = 0.99

        let restored = editable.toDescriptor()
        XCTAssertEqual(restored.intensityCurvePoints[1].value, 0.99, accuracy: 0.0001)
    }

    // MARK: - EditableCurvePoint clamping

    func testCurvePointValueClamped() {
        let point = EditableCurvePoint(time: 1.0, value: 2.5)
        XCTAssertEqual(point.value, 1.0, accuracy: 0.0001)

        let point2 = EditableCurvePoint(time: 1.0, value: -0.5)
        XCTAssertEqual(point2.value, 0.0, accuracy: 0.0001)
    }

    func testCurvePointTimeNotNegative() {
        let point = EditableCurvePoint(time: -1.0, value: 0.5)
        XCTAssertEqual(point.time, 0.0, accuracy: 0.0001)
    }

    // MARK: - EditableTransient clamping

    func testTransientIntensitySharpnessClamped() {
        let t = EditableTransient(time: 0.5, intensity: 3.0, sharpness: -0.2)
        XCTAssertEqual(t.intensity, 1.0, accuracy: 0.0001)
        XCTAssertEqual(t.sharpness, 0.0, accuracy: 0.0001)
    }
}
