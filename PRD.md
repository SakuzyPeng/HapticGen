# Product Requirements Document
# AudioHapticGenerator

**版本**：1.0
**日期**：2026-02-28
**平台**：iOS 26+，Swift 6.0

---

## 1. 产品概述

### 1.1 产品定位

AudioHapticGenerator 是一款面向内容创作者和音频工程师的 iOS 工具应用，能够从音频文件自动生成 Apple Haptic and Audio Pattern（AHAP）文件，并支持与音频、视频内容的同步播放。

### 1.2 核心价值

- **自动化**：无需手动编写 JSON，从音频内容自动提取触觉特征
- **专业性**：支持从立体声到 22.2 声道的全格式多声道音频
- **灵活性**：用户可精细控制哪些声道的哪些特征映射到触觉参数
- **验证闭环**：生成后可立即在应用内预览最终效果，支持视频+音频+触觉三者同步

### 1.3 目标用户

- 需要为 App 或游戏制作触觉素材的开发者
- 制作沉浸式体验（视频/音频+触觉）的内容创作者
- 使用多声道混音工具（如 MacinRender-ADM-Tool）的音频工程师

---

## 2. 功能需求

### 2.1 音频导入

| ID | 需求 | 优先级 |
|----|------|--------|
| F-01 | 支持通过系统文件选择器导入音频文件 | P0 |
| F-02 | 支持格式：WAV、CAF、M4A、MP3、AIFF | P0 |
| F-03 | 导入后自动检测声道数并匹配声道布局 | P0 |
| F-04 | 显示文件名、声道数、时长等基本信息 | P1 |

**支持的声道布局**（对齐 MacinRender-ADM-Tool）：

| 布局 | 声道数 | 声道标签 |
|------|--------|---------|
| 双耳 Binaural | 2ch | L R |
| 7.1 | 8ch | L R C LFE Rls Rrs Ls Rs |
| 7.1.4（Atmos） | 12ch | +Vhl Vhr Ltr Rtr |
| 9.1.6（Atmos） | 16ch | +Lw Rw Ltm Rtm |
| CICP Layout 13（22.2） | 24ch | ITU-R BS.2051-3 |

非标准声道数则按 Ch1, Ch2... 顺序命名。

### 2.2 多声道音频分析

| ID | 需求 | 优先级 |
|----|------|--------|
| F-10 | 每个声道独立进行 FFT 频谱分析 | P0 |
| F-11 | 每声道提取：RMS 能量、频谱重心、瞬态检测三项特征 | P0 |
| F-12 | 支持最多 24 声道的并行分析 | P0 |
| F-13 | 分块流式处理，避免长音频内存溢出（块大小 30 秒） | P0 |
| F-14 | 分析进度指示 | P1 |

**分析参数**：

| 参数 | 值 | 说明 |
|------|-----|------|
| FFT 大小 | 2048 | 频率分辨率 ~21.5Hz @ 44.1kHz |
| Hop 大小 | 512 | 时间分辨率 ~11.6ms |
| 窗函数 | Hann | 减少频谱泄漏 |
| 瞬态冷却期 | 30ms | 防止重复触发 |

**提取的特征**：

- **RMS 能量**：归一化 0~1，映射到触觉 Intensity
- **频谱重心**：对数映射归一化 0~1，映射到触觉 Sharpness（高值=清脆，低值=沉闷）
- **瞬态**：Spectral Flux 算法，输出 isTransient 布尔值 + 强度 0~1

### 2.3 声道映射配置

| ID | 需求 | 优先级 |
|----|------|--------|
| F-20 | 用户可为 Intensity、Sharpness、Transient 分别选择来源声道 | P0 |
| F-21 | 每个来源声道可设置权重（0~1），支持加权混合 | P0 |
| F-22 | 根据声道布局自动生成合理的默认映射 | P0 |
| F-23 | 支持添加/删除声道来源 | P1 |
| F-24 | 修改映射后立即重新生成并更新波形预览 | P1 |

**默认映射策略**（7.1 布局示例）：

| 触觉参数 | 来源声道 | 理由 |
|---------|---------|------|
| Intensity | LFE(1.0) + L(0.5) + R(0.5) | 低频能量驱动振动强度 |
| Sharpness | L(0.7) + R(0.7) + C(0.3) | 主声道高频内容驱动锐度 |
| Transient | L(0.8) + R(0.8) + C(0.5) | 主声道检测击打/冲击 |

**混合算法**：加权平均（归一化权重之和为 1）；瞬态取各来源声道的最大强度值。

### 2.4 触觉 Pattern 生成

| ID | 需求 | 优先级 |
|----|------|--------|
| F-30 | 生成符合 AHAP 1.0 规范的触觉 pattern | P0 |
| F-31 | 使用 HapticContinuous + ParameterCurve 作为主体结构 | P0 |
| F-32 | 在瞬态时间点叠加 HapticTransient 事件 | P0 |
| F-33 | 参数曲线控制点数量受 eventDensity 调控 | P0 |
| F-34 | density < 1.0 时使用 Ramer-Douglas-Peucker 算法简化曲线 | P1 |

**AHAP 结构**：

```
Pattern
├── HapticContinuous（覆盖全时长，intensity=0.5, sharpness=0.5）
├── HapticTransient × N（在每个瞬态时间点）
├── ParameterCurve: HapticIntensityControl（控制点序列）
└── ParameterCurve: HapticSharpnessControl（控制点序列）
```

### 2.5 用户参数调整

| ID | 需求 | 优先级 |
|----|------|--------|
| F-40 | 提供 4 个全局调整滑块 | P0 |
| F-41 | 播放中拖动滑块时通过 sendParameters 即时更新触觉 | P0 |
| F-42 | 松手后 300ms debounce 重建完整 pattern | P0 |

**调整参数**：

| 参数 | 范围 | 默认值 | 作用 |
|------|------|--------|------|
| 强度倍率 | 0.2~2.0 | 1.0 | Intensity 整体缩放 |
| 清晰度偏移 | -0.5~+0.5 | 0.0 | Sharpness 整体偏移 |
| 事件密度 | 0.2~3.0 | 1.0 | 参数曲线控制点间隔 |
| 瞬态灵敏度 | 0.0~1.0 | 0.5 | 瞬态检测阈值 |

### 2.6 编辑模式播放（预览）

| ID | 需求 | 优先级 |
|----|------|--------|
| F-50 | 支持音频与触觉同步播放预览 | P0 |
| F-51 | 支持播放/暂停/进度拖动 | P0 |
| F-52 | 播放中实时反映参数滑块变化（sendParameters） | P0 |
| F-53 | Seek 操作后音频与触觉保持同步 | P1 |
| F-54 | 检测设备是否支持触觉，不支持时禁用相关功能并提示 | P0 |
| F-55 | 处理应用进入后台时引擎中断/恢复 | P1 |

**同步机制**：先启动 CHHapticAdvancedPatternPlayer，紧接启动 AVAudioPlayer，两者延迟 < 2ms（人体感知阈值 > 10ms）。

### 2.7 导出

| ID | 需求 | 优先级 |
|----|------|--------|
| F-60 | 导出为标准 .ahap 文件（JSON 格式，Version 1.0） | P0 |
| F-61 | 支持通过系统 Share Sheet 分享 | P0 |
| F-62 | 支持通过 Files App 保存到本地 | P1 |
| F-63 | 导出文件名默认为原音频文件名 + .ahap 后缀 | P1 |

### 2.8 成品预览

| ID | 需求 | 优先级 |
|----|------|--------|
| F-70 | 支持加载导出的 .ahap 文件进行验证播放 | P0 |
| F-71 | .ahap + 音频文件同步播放 | P0 |
| F-72 | .ahap + 视频文件（含音轨）三者同步播放 | P1 |
| F-73 | 支持视频画面预览（AVPlayer + SwiftUI VideoPlayer） | P1 |
| F-74 | 导出后提供快捷入口直接进入成品预览 | P2 |

---

## 3. 非功能需求

### 3.1 性能

| 需求 | 指标 |
|------|------|
| 分析速度 | 3 分钟 stereo 音频分析时间 < 5 秒（A17 芯片） |
| 内存峰值 | 24 声道长音频分析期间峰值 < 200MB |
| Pattern 生成延迟 | 参数变更后 pattern 重建时间 < 200ms |
| UI 帧率 | 播放时波形游标更新保持 60fps |

### 3.2 兼容性

| 项目 | 要求 |
|------|------|
| 最低系统 | iOS 26.0 |
| 设备 | iPhone 8 及以上（CoreHaptics 最低要求） |
| 模拟器 | 可运行（触觉功能不可用，其余功能正常） |
| Swift | 6.0，严格并发模式 |

### 3.3 数据限制

| 项目 | 限制 | 来源 |
|------|------|------|
| ParameterCurve 控制点上限 | 16384 个/条曲线 | Apple CoreHaptics 文档 |
| 超限处理 | 自动降采样（density > 2.0 且音频 > 5 分钟时） | - |
| 支持音频格式 | WAV, CAF, M4A, MP3, AIFF | AVAudioFile 支持范围 |

---

## 4. 用户界面

### 4.1 整体结构

应用采用两个主要视图，通过 Tab 或 Navigation 切换：

- **编辑视图**：导入音频 → 配置声道映射 → 调参 → 预览 → 导出
- **成品预览视图**：加载 .ahap + 媒体文件 → 验证播放

### 4.2 编辑视图布局

```
+----------------------------------+
|  [导入音频]  filename.wav  8ch   |  音频导入区
+----------------------------------+
|  声道映射                         |  声道映射配置区
|  Intensity:  LFE ●●● L ●○○      |
|  Sharpness:  L ●●○  R ●●○       |
|  Transient:  L ●●●  R ●●●       |
+----------------------------------+
|  ▁▃▅▇▅▃▁▃▅▇█▇▅▃▁▃▅▇▅▃         |  波形可视化
|  ↑ 瞬态标记                       |
+----------------------------------+
|  强度倍率    ──────●──────  1.0  |  参数调整区
|  清晰度偏移  ─────●───────  0.0  |
|  事件密度    ──────●──────  1.0  |
|  瞬态灵敏度  ──────●──────  0.5  |
+----------------------------------+
|  [◀◀]  [▶ / ‖]  [▶▶]  0:00/3:30 |  播放控制
+----------------------------------+
|  [导出 .ahap]        [分享]       |  导出区
+----------------------------------+
```

### 4.3 声道映射配置区

三个折叠面板（Intensity / Sharpness / Transient），每个面板内：

- 当前声道列表，每行：声道标签（L / LFE / ...）+ 权重滑块（0~1）+ 删除按钮
- "+" 按钮弹出可用声道列表供选择
- 2ch stereo 时简化为仅显示 L/R 两行

### 4.4 波形可视化区

基于 SwiftUI Canvas 绘制，高度 160pt：

- **蓝色柱状图**：当前混合后的 Intensity 值（随分析帧密度绘制）
- **橙色竖线**：瞬态事件位置标记
- **红色竖线**：当前播放游标（60fps 更新）
- 支持点击切换查看单个声道的原始波形

### 4.5 成品预览视图布局

```
+----------------------------------+
|  [视频画面]  或  [音频封面占位图]  |
|                                  |
|                                  |
+----------------------------------+
|  AHAP:   exported.ahap [更换]    |
|  音频:   song.wav      [更换]    |
|  视频:   clip.mp4      [添加]    |
+----------------------------------+
|  [◀◀]  [▶ / ‖]  [▶▶]  0:00/3:30|
+----------------------------------+
```

---

## 5. 技术架构

### 5.1 技术栈

| 层级 | 技术 |
|------|------|
| 语言 | Swift 6.0（严格并发） |
| UI 框架 | SwiftUI |
| 音频分析 | AVFoundation + Accelerate（vDSP） |
| 触觉引擎 | CoreHaptics |
| 播放 | AVAudioPlayer（编辑预览）/ AVPlayer（成品视频） |
| 并发 | Swift Concurrency（async/await）+ NSLock |

### 5.2 模块划分

```
Core/
├── AudioAnalyzer      多声道 FFT 分析（移植自 LGP3）
├── HapticGenerator    跨声道加权混合 → AHAP 生成
├── HapticPlayer       编辑模式播放（实时参数调整）
├── ProductionPlayer   成品预览播放（.ahap + 音视频同步）
└── HapticExporter     CHHapticPattern → .ahap 文件

Models/
├── ChannelLayout      声道布局定义（5 种格式）
├── AudioAnalysisResult 单/多声道分析结果
├── ChannelMapping     跨声道特征映射配置
├── GeneratorSettings  用户调整参数
└── HapticPatternDescriptor 触觉 pattern 中间表示

ViewModels/
└── ProjectViewModel   @Observable 状态管理

UI/
├── ImportSection
├── ChannelMappingSection
├── WaveformView
├── ControlsSection
├── PlaybackBar
├── ExportSection
└── ProductionPreviewView
```

### 5.3 数据流

```
音频文件
  → AudioAnalyzer.analyze()
  → MultiChannelAnalysisResult（每声道独立 RMS/重心/瞬态）
  → HapticGenerator.generate(mapping:settings:)
  → HapticPatternDescriptor
  → CHHapticPattern（用于播放）
  → .ahap 文件（用于导出）
```

### 5.4 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| AHAP 结构 | HapticContinuous + ParameterCurve | 比逐帧 Transient 更平滑、更高效 |
| 实时调参 | sendParameters（非重建） | 播放中无缝调整，延迟 < 1ms |
| 多声道分析 | 一次读取 buffer，按声道拆分 | 避免多次 I/O，效率最优 |
| 播放同步 | haptic 先 start，audio 紧接 | 简单可靠，误差 < 2ms |
| 线程安全 | NSLock + @unchecked Sendable | 与 LGP3 项目保持一致 |

---

## 6. 验收标准

| 场景 | 预期结果 |
|------|---------|
| 导入 stereo 音频 | 显示 2ch，L/R 声道标签正确 |
| 导入 7.1.4 音频 | 显示 12ch，所有声道标签正确 |
| 修改声道映射 | 波形实时更新，重新生成 pattern |
| 播放中拖动强度滑块 | 触觉强度即时响应，无停顿 |
| 松手后 | 300ms 内 pattern 重建完成 |
| 导出 .ahap | 格式合法，可被 CoreHaptics 加载 |
| 成品预览（音频） | 触觉与音频同步，误差 < 10ms |
| 成品预览（视频） | 视频/音频/触觉三者同步 |
| 不支持触觉的设备 | 显示提示，其余功能可用 |
| 24 声道长音频 | 分析过程内存 < 200MB，无崩溃 |

---

## 7. 项目边界（Out of Scope）

- 不支持录音（仅支持导入现有文件）
- 不支持直接编辑 AHAP 时间轴（这是 Lofelt Studio 等专业工具的职责）
- 不支持 watchOS（CoreHaptics 不支持 watchOS）
- 不支持 macOS 原生（可通过 Mac Catalyst 运行，但触觉功能不可用）
- 不支持 AHAP 中的 AudioCustom 事件（仅生成触觉事件，不嵌入音频）
