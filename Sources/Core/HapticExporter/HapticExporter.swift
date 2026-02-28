import Foundation
import CoreHaptics

public final class HapticExporter: @unchecked Sendable {
    public static let maxControlPointCount = 16384

    public init() {}

    public func exportAHAP(_ descriptor: HapticPatternDescriptor, to url: URL) throws {
        do {
            let dictionary = ahapDictionary(from: descriptor)
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            throw AudioHapticError.exportFailed(error.localizedDescription)
        }
    }

    public func makePattern(_ descriptor: HapticPatternDescriptor) throws -> CHHapticPattern {
        do {
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("ahap")
            try exportAHAP(descriptor, to: temporaryURL)
            return try CHHapticPattern(contentsOf: temporaryURL)
        } catch {
            throw AudioHapticError.exportFailed("无法构建 CHHapticPattern: \(error.localizedDescription)")
        }
    }

    private func ahapDictionary(from descriptor: HapticPatternDescriptor) -> [String: Any] {
        let intensityPoints = downsampleIfNeeded(descriptor.intensityCurvePoints)
        let sharpnessPoints = downsampleIfNeeded(descriptor.sharpnessCurvePoints)

        var pattern: [[String: Any]] = []

        pattern.append([
            "Event": [
                "Time": descriptor.continuousEvent.startTime,
                "EventType": "HapticContinuous",
                "EventDuration": descriptor.continuousEvent.duration,
                "EventParameters": [
                    ["ParameterID": "HapticIntensity", "ParameterValue": descriptor.continuousEvent.baseIntensity],
                    ["ParameterID": "HapticSharpness", "ParameterValue": descriptor.continuousEvent.baseSharpness]
                ]
            ]
        ])

        for transient in descriptor.transientEvents {
            pattern.append([
                "Event": [
                    "Time": transient.time,
                    "EventType": "HapticTransient",
                    "EventParameters": [
                        ["ParameterID": "HapticIntensity", "ParameterValue": transient.intensity],
                        ["ParameterID": "HapticSharpness", "ParameterValue": transient.sharpness]
                    ]
                ]
            ])
        }

        pattern.append([
            "ParameterCurve": [
                "ParameterID": "HapticIntensityControl",
                "Time": 0,
                "ParameterCurveControlPoints": intensityPoints.map {
                    ["Time": $0.time, "ParameterValue": $0.value]
                }
            ]
        ])

        pattern.append([
            "ParameterCurve": [
                "ParameterID": "HapticSharpnessControl",
                "Time": 0,
                "ParameterCurveControlPoints": sharpnessPoints.map {
                    ["Time": $0.time, "ParameterValue": $0.value]
                }
            ]
        ])

        return [
            "Version": 1,
            "Pattern": pattern
        ]
    }

    private func downsampleIfNeeded(_ points: [CurvePoint]) -> [CurvePoint] {
        guard !points.isEmpty else {
            return [CurvePoint(time: 0, value: 0.5)]
        }

        guard points.count > Self.maxControlPointCount else {
            return points
        }

        let strideValue = Double(points.count - 1) / Double(Self.maxControlPointCount - 1)
        var output: [CurvePoint] = []
        output.reserveCapacity(Self.maxControlPointCount)

        for index in 0..<Self.maxControlPointCount {
            let sourceIndex = Int((Double(index) * strideValue).rounded())
            output.append(points[min(sourceIndex, points.count - 1)])
        }

        return output
    }
}
