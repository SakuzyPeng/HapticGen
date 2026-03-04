import Foundation

public struct GeneratorSettings: Sendable, Equatable {
    public var intensityScale: Float
    public var sharpnessBias: Float
    public var eventDensity: Float
    public var transientSensitivity: Float

    public init(
        intensityScale: Float = 1.0,
        sharpnessBias: Float = 0.0,
        eventDensity: Float = 1.0,
        transientSensitivity: Float = 0.5
    ) {
        self.intensityScale = Self.clamp(intensityScale, min: 0.2, max: 2.0)
        self.sharpnessBias = Self.clamp(sharpnessBias, min: -0.5, max: 0.5)
        self.eventDensity = Self.clamp(eventDensity, min: 0.2, max: 3.0)
        self.transientSensitivity = Self.clamp(transientSensitivity, min: 0.0, max: 1.0)
    }

    private static func clamp(_ value: Float, min lower: Float, max upper: Float) -> Float {
        Swift.max(lower, Swift.min(upper, value))
    }
}
