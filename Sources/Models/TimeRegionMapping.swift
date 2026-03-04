import Foundation

/// 时间轴上某一段区域内使用的声道权重配置
public struct WeightRegion: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var mapping: ChannelMapping

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        mapping: ChannelMapping
    ) {
        self.id = id
        self.startTime = max(0, startTime)
        self.endTime = max(max(0, startTime), endTime)
        self.mapping = mapping
    }

    public var duration: TimeInterval { endTime - startTime }
}

/// 时间轴上的分段声道权重映射
///
/// - `regions` 按 startTime 排序，相邻区域不重叠
/// - 未被任何区域覆盖的时间段使用 `defaultMapping`
public struct TimeRegionMapping: Sendable, Equatable {
    public var defaultMapping: ChannelMapping
    public var regions: [WeightRegion]

    public init(defaultMapping: ChannelMapping, regions: [WeightRegion] = []) {
        self.defaultMapping = defaultMapping
        self.regions = regions.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - 查询

    /// 查询给定时间点的有效 ChannelMapping（线性扫描，区域数通常 < 20）
    public func mapping(at time: TimeInterval) -> ChannelMapping {
        for region in regions where time >= region.startTime && time < region.endTime {
            return region.mapping
        }
        return defaultMapping
    }

    // MARK: - 修改

    /// 添加新区域，自动裁剪与现有区域的重叠
    public mutating func addRegion(_ region: WeightRegion) {
        var newStart = region.startTime
        var newEnd = region.endTime
        guard newStart < newEnd else { return }

        var updated: [WeightRegion] = []
        for existing in regions {
            if existing.endTime <= newStart || existing.startTime >= newEnd {
                // 不重叠，保留
                updated.append(existing)
            } else if existing.startTime < newStart && existing.endTime > newEnd {
                // 新区域完全被包含在已有区域内 -> 分割为两段
                var left = existing
                left.endTime = newStart
                var right = existing
                right = WeightRegion(id: UUID(), startTime: newEnd, endTime: existing.endTime, mapping: existing.mapping)
                updated.append(left)
                updated.append(right)
            } else if existing.startTime < newStart {
                // 已有区域在左侧重叠 -> 裁剪右边界
                var trimmed = existing
                trimmed.endTime = newStart
                updated.append(trimmed)
            } else if existing.endTime > newEnd {
                // 已有区域在右侧重叠 -> 裁剪左边界
                var trimmed = existing
                trimmed.startTime = newEnd
                updated.append(trimmed)
            }
            // 完全被新区域覆盖 -> 丢弃
        }

        updated.append(WeightRegion(id: region.id, startTime: newStart, endTime: newEnd, mapping: region.mapping))
        regions = updated.sorted { $0.startTime < $1.startTime }
    }

    /// 删除指定 ID 的区域
    public mutating func removeRegion(id: UUID) {
        regions.removeAll { $0.id == id }
    }

    /// 调整指定区域的边界时间，自动约束不超出相邻区域
    public mutating func resizeRegion(id: UUID, newStart: TimeInterval?, newEnd: TimeInterval?) {
        guard let idx = regions.firstIndex(where: { $0.id == id }) else { return }

        var region = regions[idx]
        let prevEnd = idx > 0 ? regions[idx - 1].endTime : 0
        let nextStart = idx < regions.count - 1 ? regions[idx + 1].startTime : .greatestFiniteMagnitude

        if let s = newStart {
            region.startTime = min(max(s, prevEnd), region.endTime - 0.001)
        }
        if let e = newEnd {
            region.endTime = max(min(e, nextStart), region.startTime + 0.001)
        }

        regions[idx] = region
    }
}
