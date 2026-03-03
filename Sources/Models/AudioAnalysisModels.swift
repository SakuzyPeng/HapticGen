import Foundation

public enum WindowFunction: String, Sendable {
    case hann
}

public struct AnalyzerSettings: Sendable {
    public var fftSize: Int
    public var hopSize: Int
    public var windowFunction: WindowFunction
    public var blockDuration: TimeInterval
    public var transientCooldown: TimeInterval

    public init(
        fftSize: Int = 2048,
        hopSize: Int = 512,
        windowFunction: WindowFunction = .hann,
        blockDuration: TimeInterval = 30,
        transientCooldown: TimeInterval = 0.03
    ) {
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.windowFunction = windowFunction
        self.blockDuration = blockDuration
        self.transientCooldown = transientCooldown
    }
}

public struct ChannelFeatureFrame: Sendable, Equatable {
    public let time: TimeInterval
    public let rms: Float
    public let spectralCentroidNorm: Float
    public let transientStrength: Float
    public let isTransient: Bool
    public let bandEnergy: SpectralBandEnergy

    public init(
        time: TimeInterval,
        rms: Float,
        spectralCentroidNorm: Float,
        transientStrength: Float,
        isTransient: Bool,
        bandEnergy: SpectralBandEnergy = .init()
    ) {
        self.time = time
        self.rms = rms
        self.spectralCentroidNorm = spectralCentroidNorm
        self.transientStrength = transientStrength
        self.isTransient = isTransient
        self.bandEnergy = bandEnergy
    }
}

public struct SpectralBandEnergy: Sendable, Equatable {
    public let sub: Float
    public let kick: Float
    public let low: Float
    public let vocal: Float
    public let presence: Float

    public init(
        sub: Float = 0,
        kick: Float = 0,
        low: Float = 0,
        vocal: Float = 0,
        presence: Float = 0
    ) {
        self.sub = Self.clamp01(sub)
        self.kick = Self.clamp01(kick)
        self.low = Self.clamp01(low)
        self.vocal = Self.clamp01(vocal)
        self.presence = Self.clamp01(presence)
    }

    private static func clamp01(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}

public struct ChannelAnalysisResult: Sendable, Equatable {
    public let label: String
    public let frames: [ChannelFeatureFrame]

    public init(label: String, frames: [ChannelFeatureFrame]) {
        self.label = label
        self.frames = frames
    }
}

public struct MultiChannelAnalysisResult: Sendable, Equatable {
    public let duration: TimeInterval
    public let sampleRate: Double
    public let layout: ChannelLayout
    public let channels: [ChannelAnalysisResult]

    public init(duration: TimeInterval, sampleRate: Double, layout: ChannelLayout, channels: [ChannelAnalysisResult]) {
        self.duration = duration
        self.sampleRate = sampleRate
        self.layout = layout
        self.channels = channels
    }
}
