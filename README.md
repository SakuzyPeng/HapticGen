# Haptic Gen

中文 | [English](README.en.md)

一个 iOS 工具应用，从多声道音频文件自动生成 Apple AHAP（Haptic and Audio Pattern）触觉文件。支持立体声到 22.2 声道，使用 FFT 频谱分析提取触觉特征，并支持音频与触觉同步播放预览。

**当前版本为可行性验证的演示版本（0.1.0-alpha）。**

> [!WARNING]
> 本项目仍处于早期开发阶段。zip 导入导出功能尚在验证中，跨设备播放可能存在问题。不推荐用于生产环境。

## 功能

- **多声道音频分析**：支持 2ch 至 24ch（22.2 声道标准）
  - 使用 Accelerate/vDSP 进行 FFT 频谱分析
  - 分块流式处理，支持长音频文件（默认 30s 块）
  - 每声道独立并行分析，充分利用多核

- **触觉特征提取**
  - RMS 强度（intensity）
  - 频谱重心（spectral centroid → sharpness）
  - 瞬态检测（transient events）

- **AHAP 1.0 生成**
  - 跨声道加权混合（支持自定义权重配置）
  - 参数曲线简化（Ramer-Douglas-Peucker 算法，16384 控制点上限）
  - Transient / Continuous / ParameterCurve 三种事件类型覆盖

- **Haptic Trailer 打包**（验证中）
  - 生成 HLS 清单 (.m3u8) + AHAP + 音频的 zip 包
  - 相对路径引用，跨设备解压后自动解析
  - 一键分享完整包，接收方用本 App 打开即可播放

- **实时播放预览**
  - 音频与触觉同步播放（音频先 start，触觉紧接）
  - 支持暂停、Seek、停止
  - 实时参数调整（强度 / 清晰度）

## 系统要求

- iOS 26.0+
- 真机播放触觉（iPhone 8 及以上，模拟器无触觉反馈但其他功能正常）
- 音频格式：WAV, CAF, M4A, MP3, AIFF（由 AVAudioFile 支持）

## 安装 & 使用

本项目使用 **XcodeGen** 管理项目配置。不要提交 .xcodeproj，而是通过 project.yml 生成。

### 初次设置

```bash
# 1. 安装 XcodeGen（如未安装）
brew install xcodegen

# 2. 生成 Xcode 项目（修改 project.yml 后也需要重新生成）
xcodegen generate

# 3. 打开项目
open HapticGen.xcodeproj
```

### 构建

```bash
# Xcode 中构建（Cmd+B）或命令行
xcodebuild build -scheme HapticGen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### 运行

在 Xcode 中按 Cmd+R，或在真机用 Xcode 直接连接安装（自动签名）。

## 工作流程

### 1. 导入音频

点击"导入音频" -> 选择本地多声道音频文件

支持的格式：WAV、M4A、MP3、AIFF、CAF 等

### 2. 分析

点击"Analyze"
- 自动检测声道数 & 布局（立体声 / 7.1 / 7.1.4 等）
- FFT 分析提取触觉特征（进度条显示）
- 完成后显示总帧数 & 布局

### 3. 生成

点击"Generate" -> 调整参数（可实时预览）

可调参数：
- 强度倍率：0.2x ~ 2.0x（整体触觉幅度）
- 清晰度偏移：-0.5 ~ +0.5（频率感知）
- 事件密度：0.2x ~ 3.0x（瞬态触觉频繁度）
- 瞬态灵敏度：0.0 ~ 1.0（瞬态检测阈值）

结果显示：瞬态事件数量、曲线控制点数

### 4. 播放 & 导出

- Play/Pause：实时播放测试（音频 + 触觉同步）
- Export .ahap：导出 AHAP JSON 文件（可用于其他应用）
- Package Haptic Trailer：打包为 zip（音频 + AHAP + 清单）

### 5. 分享 & 接收

**发送方**：
- 点击"Package Haptic Trailer" -> 弹出播放器 -> 点击分享 -> 分享 .zip 文件

**接收方**：
- 通过 AirDrop / 邮件 / Files App 接收 .zip
- 在 Files App 长按 -> "用 Haptic Gen 打开"
- App 自动解压并进入播放界面，点击▶播放

## 示例文件

- [2ch_haptic_trailer.ahap](Samples/2ch_haptic_trailer.ahap) - 生成的 AHAP 样品（2ch 音频）
  - 在 iPhone Files App 中打开此文件即可预览
  - 包含 HapticContinuous（持续触觉）和 HapticTransient（瞬态触觉）事件

## 已知问题 & 待做

**验证中：**
- zip 导入导出
  - m3u8 使用相对路径，理论上应该有效
  - 需要在真机上跨设备测试

**待优化：**
- 性能优化：8ch FLAC 分析在模拟器上约 1.95s（RTF ≈ 164×），可接受但仍有优化空间
- UI 完善：目前为调试仪表板（DebugDashboardView），尚未美化
- 触觉曲线降采样：可进一步优化
- 分析进度显示：仅为百分比，无详细信息

**未来扩展：**
- 触觉预设（preset）支持
- 音频可视化
- 批量处理

## 架构概览

```
音频文件
  ↓
AudioAnalyzer.analyze()          FFT 分析，并行处理多声道
  ↓
MultiChannelAnalysisResult       RMS / 频谱重心 / 瞬态帧序列
  ↓
HapticGenerator.generate()       跨声道加权混合
  ↓
HapticPatternDescriptor          触觉模式中间表示
  ↓
HapticExporter                   生成 CHHapticPattern + AHAP JSON
  ↓
HapticPlayer / HapticTrailerPlayer  播放预览
```

## 技术栈

- Swift 6.0（严格并发模式）
- CoreHaptics（触觉引擎）
- AVFoundation（音频处理）
- Accelerate / vDSP（向量化 FFT 计算）
- ZIPFoundation（zip 打包/解压）
- SwiftUI（UI 界面）
- XcodeGen（项目配置）

## 测试

```bash
# 运行所有测试
xcodebuild test -scheme HapticGen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 运行单个测试类
xcodebuild test -scheme HapticGen \
  -only-testing HapticGenTests/AudioAnalyzerTests

# 运行基准测试（可选，需要样本音频）
xcodebuild test -scheme HapticGen \
  -only-testing HapticGenTests/AnalysisBenchmarkTests
```

## CI/CD（产出应用包）

仓库内置了 GitHub Actions 流水线：[`.github/workflows/build-packages.yml`](.github/workflows/build-packages.yml)。

1. `push master`：自动构建并上传 `HapticGen-simulator-app.zip` 与未签名 IPA 包（用于后续本地二次签名）。
2. `workflow_dispatch`：
   - `package_type=simulator`：只产出模拟器包。
   - `package_type=unsigned`：只产出未签名 IPA（用于后续本地二次签名）。
   - `package_type=signed`：只产出签名 IPA。
   - `package_type=both`：产出模拟器包 + 未签名 IPA。
   - `package_type=all`：产出模拟器包 + 未签名 IPA + 签名 IPA。

默认 `push master` 产出：
1. `HapticGen-simulator-app.zip`
2. `HapticGen-unsigned-ipa`（artifact 名）

未签名 IPA 不能直接安装到 iPhone，需要用户用 Sideloadly/AltStore/ios-app-signer 等工具二次签名后再侧载。

签名 IPA 需要预先配置以下 `GitHub Secrets`：

1. `IOS_CERTIFICATE_P12_BASE64`
2. `IOS_CERTIFICATE_PASSWORD`
3. `IOS_PROVISIONING_PROFILE_BASE64`
4. `IOS_EXPORT_OPTIONS_BASE64`
5. `IOS_KEYCHAIN_PASSWORD`
6. `IOS_TEAM_ID`

仅 `signed` / `all` 模式需要签名 secrets。若未配置完整，`Build Signed IPA` 会在 `Validate signing secrets` 步骤失败。

可参考示例导出选项文件：[`scripts/ci/ExportOptions.plist.example`](scripts/ci/ExportOptions.plist.example)。

Base64 编码示例：

```bash
base64 < certificate.p12 | tr -d '\n'
base64 < profile.mobileprovision | tr -d '\n'
base64 < ExportOptions.plist | tr -d '\n'
```

## 贡献

本项目为个人可行性验证项目，暂不接受外部贡献。如有建议或发现 bug，欢迎在 GitHub Issues 提出。

## 许可证

MIT License © 2026 Sakuzy Peng
