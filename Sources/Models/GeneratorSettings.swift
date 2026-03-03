import Foundation

public struct GeneratorSettings: Sendable, Equatable {
    public var intensityScale: Float
    public var sharpnessBias: Float
    public var eventDensity: Float
    public var transientSensitivity: Float
    public var transientMinInterval: TimeInterval
    public var transientMaxPerSecond: Int

    public init(
        intensityScale: Float = 1.0,
        sharpnessBias: Float = 0.0,
        eventDensity: Float = 1.0,
        transientSensitivity: Float = 0.5,
        transientMinInterval: TimeInterval = 0.08,
        transientMaxPerSecond: Int = 8
    ) {
        self.intensityScale = Self.clamp(intensityScale, min: 0.2, max: 2.0)
        self.sharpnessBias = Self.clamp(sharpnessBias, min: -0.5, max: 0.5)
        self.eventDensity = Self.clamp(eventDensity, min: 0.2, max: 3.0)
        self.transientSensitivity = Self.clamp(transientSensitivity, min: 0.0, max: 1.0)
        self.transientMinInterval = Self.clampTime(transientMinInterval, min: 0.02, max: 0.5)
        self.transientMaxPerSecond = max(1, min(40, transientMaxPerSecond))
    }

    private static func clamp(_ value: Float, min lower: Float, max upper: Float) -> Float {
        Swift.max(lower, Swift.min(upper, value))
    }

    private static func clampTime(_ value: TimeInterval, min lower: TimeInterval, max upper: TimeInterval) -> TimeInterval {
        Swift.max(lower, Swift.min(upper, value))
    }
}
