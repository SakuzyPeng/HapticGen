import Foundation

public struct CurvePoint: Sendable, Equatable {
    public let time: TimeInterval
    public let value: Float

    public init(time: TimeInterval, value: Float) {
        self.time = max(0, time)
        self.value = max(0, min(1, value))
    }
}

public struct TransientPoint: Sendable, Equatable {
    public let time: TimeInterval
    public let intensity: Float
    public let sharpness: Float

    public init(time: TimeInterval, intensity: Float, sharpness: Float) {
        self.time = max(0, time)
        self.intensity = max(0, min(1, intensity))
        self.sharpness = max(0, min(1, sharpness))
    }
}

public struct ContinuousEventDescriptor: Sendable, Equatable {
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let baseIntensity: Float
    public let baseSharpness: Float

    public init(
        startTime: TimeInterval = 0,
        duration: TimeInterval,
        baseIntensity: Float = 0.5,
        baseSharpness: Float = 0.5
    ) {
        self.startTime = max(0, startTime)
        self.duration = max(0, duration)
        self.baseIntensity = max(0, min(1, baseIntensity))
        self.baseSharpness = max(0, min(1, baseSharpness))
    }
}

public struct HapticPatternDescriptor: Sendable, Equatable {
    public let duration: TimeInterval
    public let continuousEvent: ContinuousEventDescriptor
    public let intensityCurvePoints: [CurvePoint]
    public let sharpnessCurvePoints: [CurvePoint]
    public let transientEvents: [TransientPoint]

    public init(
        duration: TimeInterval,
        continuousEvent: ContinuousEventDescriptor,
        intensityCurvePoints: [CurvePoint],
        sharpnessCurvePoints: [CurvePoint],
        transientEvents: [TransientPoint]
    ) {
        self.duration = max(0, duration)
        self.continuousEvent = continuousEvent
        self.intensityCurvePoints = intensityCurvePoints.sorted { $0.time < $1.time }
        self.sharpnessCurvePoints = sharpnessCurvePoints.sorted { $0.time < $1.time }
        self.transientEvents = transientEvents.sorted { $0.time < $1.time }
    }
}
