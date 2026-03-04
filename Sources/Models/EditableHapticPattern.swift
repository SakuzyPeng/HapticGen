import Foundation

/// 带 UUID 的可编辑曲线控制点（用于拖拽追踪）
public struct EditableCurvePoint: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var time: TimeInterval
    public var value: Float  // 0 ~ 1

    public init(id: UUID = UUID(), time: TimeInterval, value: Float) {
        self.id = id
        self.time = max(0, time)
        self.value = max(0, min(1, value))
    }

    public init(from point: CurvePoint) {
        self.id = UUID()
        self.time = point.time
        self.value = point.value
    }

    public func toCurvePoint() -> CurvePoint {
        CurvePoint(time: time, value: value)
    }
}

/// 带 UUID 的可编辑瞬态事件
public struct EditableTransient: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var time: TimeInterval
    public var intensity: Float  // 0 ~ 1
    public var sharpness: Float  // 0 ~ 1

    public init(id: UUID = UUID(), time: TimeInterval, intensity: Float, sharpness: Float) {
        self.id = id
        self.time = max(0, time)
        self.intensity = max(0, min(1, intensity))
        self.sharpness = max(0, min(1, sharpness))
    }

    public init(from point: TransientPoint) {
        self.id = UUID()
        self.time = point.time
        self.intensity = point.intensity
        self.sharpness = point.sharpness
    }

    public func toTransientPoint() -> TransientPoint {
        TransientPoint(time: time, intensity: intensity, sharpness: sharpness)
    }
}

/// HapticPatternDescriptor 的可变版本，用于时间轴编辑器
public struct EditableHapticPattern: Sendable, Equatable {
    public var duration: TimeInterval
    public var intensityCurve: [EditableCurvePoint]
    public var sharpnessCurve: [EditableCurvePoint]
    public var transients: [EditableTransient]

    public init(
        duration: TimeInterval,
        intensityCurve: [EditableCurvePoint],
        sharpnessCurve: [EditableCurvePoint],
        transients: [EditableTransient]
    ) {
        self.duration = duration
        self.intensityCurve = intensityCurve
        self.sharpnessCurve = sharpnessCurve
        self.transients = transients
    }

    public init(from descriptor: HapticPatternDescriptor) {
        self.duration = descriptor.duration
        self.intensityCurve = descriptor.intensityCurvePoints.map { EditableCurvePoint(from: $0) }
        self.sharpnessCurve = descriptor.sharpnessCurvePoints.map { EditableCurvePoint(from: $0) }
        self.transients = descriptor.transientEvents.map { EditableTransient(from: $0) }
    }

    /// 转回不可变的 HapticPatternDescriptor
    public func toDescriptor() -> HapticPatternDescriptor {
        HapticPatternDescriptor(
            duration: duration,
            continuousEvent: ContinuousEventDescriptor(duration: duration),
            intensityCurvePoints: intensityCurve.map { $0.toCurvePoint() },
            sharpnessCurvePoints: sharpnessCurve.map { $0.toCurvePoint() },
            transientEvents: transients.map { $0.toTransientPoint() }
        )
    }
}
