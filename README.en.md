# Haptic Gen

[中文](README.md) | English

An iOS tool application that automatically generates Apple AHAP (Haptic and Audio Pattern) files from multi-channel audio. Supports stereo to 22.2-channel audio with FFT-based spectrum analysis for haptic feature extraction and real-time synchronized playback preview.

**Current version is an alpha demo (0.1.0-alpha) for feasibility validation.**

> [!WARNING]
> This project is in early development. Zip import/export is under verification with potential cross-device issues. Not recommended for production use.

## Features

- **Multi-Channel Audio Analysis**: Support 2ch to 24ch (22.2-channel standard)
  - FFT spectrum analysis using Accelerate/vDSP
  - Streaming block-based processing for long audio files (default 30s blocks)
  - Per-channel parallel analysis, utilizing multi-core efficiently

- **Haptic Feature Extraction**
  - RMS intensity (intensity)
  - Spectral centroid (spectral centroid → sharpness)
  - Transient detection (transient events)

- **AHAP 1.0 Generation**
  - Cross-channel weighted blending (custom weight configuration supported)
  - Parameter curve simplification (Ramer-Douglas-Peucker algorithm, 16384 control point limit)
  - Three event types coverage: Transient / Continuous / ParameterCurve

- **Haptic Trailer Packaging** (Under Verification)
  - Generate HLS manifest (.m3u8) + AHAP + audio as a zip package
  - Relative path references, auto-resolve after cross-device extraction
  - One-click share complete package; recipients open with this app to play

- **Real-Time Playback Preview**
  - Audio and haptic synchronized playback (audio starts first, haptic follows immediately)
  - Support pause, seek, stop
  - Real-time parameter adjustment (intensity / sharpness)

## System Requirements

- iOS 26.0+
- Real device for haptic playback (iPhone 8 and above; simulator works for other features)
- Audio formats: WAV, CAF, M4A, MP3, AIFF (supported by AVAudioFile)

## Installation & Setup

This project uses **XcodeGen** to manage project configuration. Do not commit .xcodeproj; instead, generate via project.yml.

### Initial Setup

```bash
# 1. Install XcodeGen (if not installed)
brew install xcodegen

# 2. Generate Xcode project (also run after modifying project.yml)
xcodegen generate

# 3. Open project
open HapticGen.xcodeproj
```

### Build

```bash
# Build in Xcode (Cmd+B) or command line
xcodebuild build -scheme HapticGen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Run

Press Cmd+R in Xcode, or connect a real device and install via Xcode (auto-signing).

## Workflow

### 1. Import Audio

Click "Import Audio" -> Select a local multi-channel audio file

Supported formats: WAV, M4A, MP3, AIFF, CAF, etc.

### 2. Analyze

Click "Analyze"
- Auto-detect channel count & layout (stereo / 7.1 / 7.1.4, etc.)
- FFT analysis extracts haptic features (progress bar shown)
- Display total frames & layout on completion

### 3. Generate

Click "Generate" -> Adjust parameters (real-time preview available)

Adjustable parameters:
- Intensity Scale: 0.2x ~ 2.0x (overall haptic amplitude)
- Sharpness Bias: -0.5 ~ +0.5 (frequency perception)
- Event Density: 0.2x ~ 3.0x (transient haptic frequency)
- Transient Sensitivity: 0.0 ~ 1.0 (transient detection threshold)

Results display: transient event count, curve control point count

### 4. Playback & Export

- Play/Pause: Real-time test playback (audio + haptic sync)
- Export .ahap: Export AHAP JSON file (usable in other apps)
- Package Haptic Trailer: Package as zip (audio + AHAP + manifest)

### 5. Share & Receive

**Sender**:
- Click "Package Haptic Trailer" -> Player pops up -> Click share -> Share .zip file

**Receiver**:
- Receive .zip via AirDrop / Email / Files App
- Long press in Files App -> "Open with Haptic Gen"
- App auto-extracts and enters playback interface; click play button

## Sample Files

- [2ch_haptic_trailer.ahap](Samples/2ch_haptic_trailer.ahap) - Generated AHAP sample (2ch audio)
  - Open this file in iPhone Files App for preview
  - Contains HapticContinuous (continuous haptic) and HapticTransient (transient haptic) events

## Known Issues & TODO

**Under Verification:**
- Zip import/export
  - m3u8 uses relative paths, should work in theory
  - Needs real device cross-device testing

**Performance Optimizations:**
- 8ch FLAC analysis on simulator ~1.95s (RTF ≈ 164×), acceptable but room for improvement
- Haptic curve downsampling can be further optimized
- Analysis progress display: only percentage, no detailed info
- UI polish: currently debug dashboard (DebugDashboardView), needs refinement

**Future Extensions:**
- Haptic preset support
- Audio visualization
- Batch processing

## Architecture Overview

```
Audio File
  ↓
AudioAnalyzer.analyze()          FFT analysis, parallel multi-channel processing
  ↓
MultiChannelAnalysisResult       RMS / spectral centroid / transient frame sequences
  ↓
HapticGenerator.generate()       Cross-channel weighted blending
  ↓
HapticPatternDescriptor          Haptic pattern intermediate representation
  ↓
HapticExporter                   Generate CHHapticPattern + AHAP JSON
  ↓
HapticPlayer / HapticTrailerPlayer  Playback preview
```

## Tech Stack

- Swift 6.0 (strict concurrency mode)
- CoreHaptics (haptic engine)
- AVFoundation (audio processing)
- Accelerate / vDSP (vectorized FFT computation)
- ZIPFoundation (zip packaging/extraction)
- SwiftUI (UI framework)
- XcodeGen (project configuration)

## Testing

```bash
# Run all tests
xcodebuild test -scheme HapticGen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run single test class
xcodebuild test -scheme HapticGen \
  -only-testing HapticGenTests/AudioAnalyzerTests

# Run benchmark tests (optional, requires sample audio)
xcodebuild test -scheme HapticGen \
  -only-testing HapticGenTests/AnalysisBenchmarkTests
```

## CI/CD (App Package Output)

This repository includes a GitHub Actions pipeline: [`.github/workflows/build-packages.yml`](.github/workflows/build-packages.yml).

1. `push master`: automatically builds and uploads `HapticGen-simulator-app.zip` (for simulator testing).
2. `workflow_dispatch`:
   - `package_type=simulator`: build simulator package only.
   - `package_type=ipa`: build signed IPA only.
   - `package_type=both`: build both package types.

Signed IPA builds require these `GitHub Secrets`:

1. `IOS_CERTIFICATE_P12_BASE64`
2. `IOS_CERTIFICATE_PASSWORD`
3. `IOS_PROVISIONING_PROFILE_BASE64`
4. `IOS_EXPORT_OPTIONS_BASE64`
5. `IOS_KEYCHAIN_PASSWORD`
6. `IOS_TEAM_ID`

Use this export options template as reference:
[`scripts/ci/ExportOptions.plist.example`](scripts/ci/ExportOptions.plist.example).

Base64 examples:

```bash
base64 < certificate.p12 | tr -d '\n'
base64 < profile.mobileprovision | tr -d '\n'
base64 < ExportOptions.plist | tr -d '\n'
```

## Contributing

This project is a personal feasibility validation project and does not currently accept external contributions. For suggestions or bug reports, please open a GitHub Issue.

## License

MIT License © 2026 Sakuzy Peng
