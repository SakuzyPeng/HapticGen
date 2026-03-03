# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

AudioHapticGenerator 是一个 iOS 工具应用，从多声道音频文件自动生成 Apple AHAP（Haptic and Audio Pattern）触觉文件。支持立体声到 22.2 声道（24ch），使用 FFT 频谱分析提取触觉特征，并支持音频与触觉同步播放预览。

- **平台**：iOS 26.0+，Swift 6.0 严格并发模式
- **依赖框架**：CoreHaptics、AVFoundation、Accelerate（vDSP）、SwiftUI
- **Bundle ID**：com.sakuzy.AudioHapticGenerator

## 构建与测试命令

项目使用 XcodeGen 管理配置，`project.yml` 是项目的真实来源。

```bash
# 从 project.yml 重新生成 Xcode 项目（修改 project.yml 后需要执行）
xcodegen generate

# 构建项目
xcodebuild build -scheme AudioHapticGenerator -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'

# 运行所有测试
xcodebuild test -scheme AudioHapticGenerator -destination 'platform=iOS Simulator,name=iPhone 16'

# 运行单个测试类
xcodebuild test -scheme AudioHapticGenerator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing AudioHapticGeneratorTests/AudioAnalyzerTests
```

在 Xcode 中：`Cmd+B` 构建，`Cmd+U` 运行所有测试，`Cmd+R` 运行应用。

## 架构与数据流

### 核心数据流

```
音频文件
  → AudioAnalyzer.analyze()         # FFT 分析，每声道独立
  → MultiChannelAnalysisResult      # 每声道 RMS/频谱重心/瞬态帧序列
  → HapticGenerator.generate()      # 跨声道加权混合
  → HapticPatternDescriptor         # 触觉模式中间表示
  → HapticExporter                  # 生成 CHHapticPattern + .ahap JSON
  → HapticPlayer                    # 音频+触觉同步播放
```

### 模块职责

**Core/**
- `AudioAnalyzer`：使用 Accelerate/vDSP 进行 FFT（大小 2048，hop 512，~11.6ms 时间分辨率），分块流式处理（30s 块）支持最多 24 声道并行分析
- `HapticGenerator`：三个特征的跨声道加权混合（Intensity=加权平均，Sharpness=加权平均，Transient=加权最大值），使用 Ramer-Douglas-Peucker 算法简化曲线，强制 16384 控制点上限
- `HapticExporter`：生成 AHAP 1.0 JSON，结构为 HapticContinuous + ParameterCurve × 2 + HapticTransient × N
- `HapticPlayer`：音频与触觉同步（haptic 先 start，audio 紧接），支持 sendParameters 实时调参，误差 < 2ms

**Models/**
- `ChannelLayout`：5 种标准布局（Binaural/7.1/7.1.4/9.1.6/22.2）+ Custom 命名
- `ChannelMapping`：三个触觉特征的声道来源权重配置，含智能默认映射（7.1 布局：Intensity 以 LFE 为主）
- `GeneratorSettings`：4 个用户参数（强度倍率 0.2~2.0、清晰度偏移 -0.5~+0.5、事件密度 0.2~3.0、瞬态灵敏度 0.0~1.0）

**ViewModels/**
- `ProjectViewModel`：`@Observable @MainActor` 中央状态管理，包含 300ms debounce 防抖重建逻辑（滑块松手后触发）

### 并发安全模式

项目使用 Swift 6.0 严格并发。核心引擎通过 `NSLock + @unchecked Sendable` 保证线程安全，UI 层全部通过 `@MainActor` 约束。异步操作使用 `async/await`。

## 关键约束与限制

- **CoreHaptics 上限**：每条 ParameterCurve 最多 16384 个控制点（超限自动降采样）
- **音频格式**：WAV、CAF、M4A、MP3、AIFF（由 AVAudioFile 支持）
- **触觉设备**：需要 iPhone 8 及以上，模拟器无触觉但其余功能正常
- **AHAP 格式**：仅生成触觉事件，不嵌入 AudioCustom 音频事件

## 测试说明

测试文件位于 `Tests/`，`TestAudioFactory` 提供合成 WAV 音频用于单元测试。集成测试 `RealAudioAHAPIntegrationTests` 测试实际 8ch 音频的完整流程（端到端：分析 → 生成 → 导出 → CHHapticPattern 加载）。
