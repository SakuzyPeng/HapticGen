import Foundation

public enum L10n {
    enum Key {
        static let commonAlertErrorTitle = "common.alert.error.title"
        static let commonButtonOK = "common.button.ok"
        static let commonPlaceholderDash = "common.placeholder.dash"

        static let languageMenuTitle = "language.menu.title"
        static let languageOptionAuto = "language.option.auto"
        static let languageOptionZhHans = "language.option.zhHans"
        static let languageOptionEn = "language.option.en"

        static let debugNavigationTitle = "debug.navigation.title"
        static let debugSectionImport = "debug.section.import"
        static let debugSectionAction = "debug.section.action"
        static let debugSectionParameters = "debug.section.parameters"
        static let debugSectionResult = "debug.section.result"
        static let debugSectionStatus = "debug.section.status"

        static let debugButtonImportAudio = "debug.button.importAudio"
        static let debugButtonAnalyze = "debug.button.analyze"
        static let debugButtonGenerate = "debug.button.generate"
        static let debugButtonPlay = "debug.button.play"
        static let debugButtonPause = "debug.button.pause"
        static let debugButtonStop = "debug.button.stop"
        static let debugButtonExportAHAP = "debug.button.exportAHAP"
        static let debugButtonPackageTrailer = "debug.button.packageTrailer"

        static let debugSliderIntensityScale = "debug.slider.intensityScale"
        static let debugSliderSharpnessBias = "debug.slider.sharpnessBias"
        static let debugSliderEventDensity = "debug.slider.eventDensity"
        static let debugSliderTransientSensitivity = "debug.slider.transientSensitivity"

        static let debugLabelFileFormat = "debug.label.file.format"
        static let debugLabelChannelFormat = "debug.label.channel.format"
        static let debugLabelDurationFormat = "debug.label.duration.format"
        static let debugLabelAnalysisFramesFormat = "debug.label.analysisFrames.format"
        static let debugLabelAnalysisFramesEmpty = "debug.label.analysisFrames.empty"
        static let debugLabelLayoutFormat = "debug.label.layout.format"
        static let debugLabelTransientCountFormat = "debug.label.transientCount.format"
        static let debugLabelTransientCountEmpty = "debug.label.transientCount.empty"
        static let debugLabelIntensityPointsFormat = "debug.label.intensityPoints.format"
        static let debugLabelSharpnessPointsFormat = "debug.label.sharpnessPoints.format"
        static let debugLabelCurvePointsEmpty = "debug.label.curvePoints.empty"
        static let debugLabelExportPathFormat = "debug.label.exportPath.format"
        static let debugLabelStrategyRatioFormat = "debug.label.strategyRatio.format"
        static let debugLabelLFEAvailableTrue = "debug.label.lfeAvailable.true"
        static let debugLabelLFEAvailableFalse = "debug.label.lfeAvailable.false"
        static let debugLabelFallbackFormat = "debug.label.fallback.format"

        static let playerNavigationTitle = "player.navigation.title"
        static let playerSectionPackageInfo = "player.section.packageInfo"
        static let playerSectionPlayback = "player.section.playback"
        static let playerSectionExport = "player.section.export"

        static let playerInfoFile = "player.info.file"
        static let playerInfoHLSTag = "player.info.hlsTag"
        static let playerInfoHapticsSupport = "player.info.hapticsSupport"
        static let playerInfoHapticsSupported = "player.info.hapticsSupported"
        static let playerInfoHapticsUnsupported = "player.info.hapticsUnsupported"

        static let playerLoading = "player.loading"
        static let playerShareButton = "player.button.share"
        static let playerShareDescription = "player.description.share"

        static let statusSelectAudio = "status.selectAudio"
        static let statusImportReady = "status.importReady"
        static let statusAnalyzing = "status.analyzing"
        static let statusAnalysisCompletedFormat = "status.analysisCompleted.format"
        static let statusGenerateCompletedFormat = "status.generateCompleted.format"
        static let statusPaused = "status.paused"
        static let statusPlaying = "status.playing"
        static let statusTrailerPackagedFormat = "status.trailerPackaged.format"
        static let statusExportSuccessFormat = "status.exportSuccess.format"
        static let statusErrorOccurred = "status.errorOccurred"

        static let errorInvalidAudioFormat = "error.invalidAudioFormat"
        static let errorUnsupportedHaptics = "error.unsupportedHaptics"
        static let errorAnalysisFailedFormat = "error.analysisFailed.format"
        static let errorGenerationFailedFormat = "error.generationFailed.format"
        static let errorExportFailedFormat = "error.exportFailed.format"
        static let errorPlaybackFailedFormat = "error.playbackFailed.format"

        static let errorDetailImportAudioFirst = "error.detail.importAudioFirst"
        static let errorDetailCompleteAnalysisFirst = "error.detail.completeAnalysisFirst"
        static let errorDetailGeneratePatternFirst = "error.detail.generatePatternFirst"
        static let errorDetailSourceAudioMissing = "error.detail.sourceAudioMissing"
        static let errorDetailPrepareFirst = "error.detail.prepareFirst"
        static let errorDetailPatternMissing = "error.detail.patternMissing"
        static let errorDetailHapticPlayerNotPrepared = "error.detail.hapticPlayerNotPrepared"
        static let errorDetailLoadManifestFirst = "error.detail.loadManifestFirst"
        static let errorDetailManifestNotFoundInZip = "error.detail.manifestNotFoundInZip"
        static let errorDetailManifestMissingAHAPURL = "error.detail.manifestMissingAHAPURL"
        static let errorDetailManifestMissingAudioURL = "error.detail.manifestMissingAudioURL"
        static let errorDetailAudioBufferCreationFailed = "error.detail.audioBufferCreationFailed"
        static let errorDetailPatternBuildFailedFormat = "error.detail.patternBuildFailed.format"
        static let errorDetailManifestEncodingFailed = "error.detail.manifestEncodingFailed"
        static let errorDetailEmptyAnalysisResult = "error.detail.emptyAnalysisResult"
        static let errorDetailNoFramesAvailable = "error.detail.noFramesAvailable"
    }

    private static let tableName = "Localizable"

    public static var commonAlertErrorTitle: String { text(Key.commonAlertErrorTitle) }
    public static var commonButtonOK: String { text(Key.commonButtonOK) }
    public static var commonPlaceholderDash: String { text(Key.commonPlaceholderDash) }

    public static var languageMenuTitle: String { text(Key.languageMenuTitle) }

    public static func languageOption(_ language: AppLanguage) -> String {
        switch language {
        case .auto:
            return text(Key.languageOptionAuto)
        case .zhHans:
            return text(Key.languageOptionZhHans)
        case .en:
            return text(Key.languageOptionEn)
        }
    }

    public static var debugNavigationTitle: String { text(Key.debugNavigationTitle) }
    public static var debugSectionImport: String { text(Key.debugSectionImport) }
    public static var debugSectionAction: String { text(Key.debugSectionAction) }
    public static var debugSectionParameters: String { text(Key.debugSectionParameters) }
    public static var debugSectionResult: String { text(Key.debugSectionResult) }
    public static var debugSectionStatus: String { text(Key.debugSectionStatus) }

    public static var debugButtonImportAudio: String { text(Key.debugButtonImportAudio) }
    public static var debugButtonAnalyze: String { text(Key.debugButtonAnalyze) }
    public static var debugButtonGenerate: String { text(Key.debugButtonGenerate) }
    public static var debugButtonPlay: String { text(Key.debugButtonPlay) }
    public static var debugButtonPause: String { text(Key.debugButtonPause) }
    public static var debugButtonStop: String { text(Key.debugButtonStop) }
    public static var debugButtonExportAHAP: String { text(Key.debugButtonExportAHAP) }
    public static var debugButtonPackageTrailer: String { text(Key.debugButtonPackageTrailer) }

    public static var debugSliderIntensityScale: String { text(Key.debugSliderIntensityScale) }
    public static var debugSliderSharpnessBias: String { text(Key.debugSliderSharpnessBias) }
    public static var debugSliderEventDensity: String { text(Key.debugSliderEventDensity) }
    public static var debugSliderTransientSensitivity: String { text(Key.debugSliderTransientSensitivity) }

    public static func debugFile(_ fileName: String) -> String {
        format(Key.debugLabelFileFormat, fileName)
    }

    public static func debugChannel(_ channelCount: Int) -> String {
        format(Key.debugLabelChannelFormat, channelCount)
    }

    public static func debugDuration(_ duration: String) -> String {
        format(Key.debugLabelDurationFormat, duration)
    }

    public static func debugAnalysisFrames(_ frames: Int) -> String {
        format(Key.debugLabelAnalysisFramesFormat, frames)
    }

    public static var debugAnalysisFramesEmpty: String { text(Key.debugLabelAnalysisFramesEmpty) }

    public static func debugLayout(_ channelCount: Int) -> String {
        format(Key.debugLabelLayoutFormat, channelCount)
    }

    public static func debugTransientCount(_ count: Int) -> String {
        format(Key.debugLabelTransientCountFormat, count)
    }

    public static var debugTransientCountEmpty: String { text(Key.debugLabelTransientCountEmpty) }

    public static func debugIntensityPoints(_ count: Int) -> String {
        format(Key.debugLabelIntensityPointsFormat, count)
    }

    public static func debugSharpnessPoints(_ count: Int) -> String {
        format(Key.debugLabelSharpnessPointsFormat, count)
    }

    public static var debugCurvePointsEmpty: String { text(Key.debugLabelCurvePointsEmpty) }

    public static func debugExportPath(_ path: String) -> String {
        format(Key.debugLabelExportPathFormat, path)
    }

    public static func debugStrategyRatio(kick: Float, vocal: Float, balanced: Float) -> String {
        format(
            Key.debugLabelStrategyRatioFormat,
            Int(clampPercent(kick)),
            Int(clampPercent(vocal)),
            Int(clampPercent(balanced))
        )
    }

    public static func debugLFEAvailable(_ isAvailable: Bool) -> String {
        text(isAvailable ? Key.debugLabelLFEAvailableTrue : Key.debugLabelLFEAvailableFalse)
    }

    public static func debugFallback(_ reasons: String) -> String {
        format(Key.debugLabelFallbackFormat, reasons)
    }

    public static var playerNavigationTitle: String { text(Key.playerNavigationTitle) }
    public static var playerSectionPackageInfo: String { text(Key.playerSectionPackageInfo) }
    public static var playerSectionPlayback: String { text(Key.playerSectionPlayback) }
    public static var playerSectionExport: String { text(Key.playerSectionExport) }

    public static var playerInfoFile: String { text(Key.playerInfoFile) }
    public static var playerInfoHLSTag: String { text(Key.playerInfoHLSTag) }
    public static var playerInfoHapticsSupport: String { text(Key.playerInfoHapticsSupport) }
    public static var playerInfoHapticsSupported: String { text(Key.playerInfoHapticsSupported) }
    public static var playerInfoHapticsUnsupported: String { text(Key.playerInfoHapticsUnsupported) }

    public static var playerLoading: String { text(Key.playerLoading) }
    public static var playerShareButton: String { text(Key.playerShareButton) }
    public static var playerShareDescription: String { text(Key.playerShareDescription) }

    public static var statusSelectAudio: String { text(Key.statusSelectAudio) }
    public static var statusImportReady: String { text(Key.statusImportReady) }
    public static var statusAnalyzing: String { text(Key.statusAnalyzing) }
    public static var statusPaused: String { text(Key.statusPaused) }
    public static var statusPlaying: String { text(Key.statusPlaying) }
    public static var statusErrorOccurred: String { text(Key.statusErrorOccurred) }

    public static func statusAnalysisCompleted(channelCount: Int) -> String {
        format(Key.statusAnalysisCompletedFormat, channelCount)
    }

    public static func statusGenerateCompleted(transientCount: Int) -> String {
        format(Key.statusGenerateCompletedFormat, transientCount)
    }

    public static func statusExportSuccess(fileName: String) -> String {
        format(Key.statusExportSuccessFormat, fileName)
    }

    public static func statusTrailerPackaged(fileName: String) -> String {
        format(Key.statusTrailerPackagedFormat, fileName)
    }

    public static var errorInvalidAudioFormat: String { text(Key.errorInvalidAudioFormat) }
    public static var errorUnsupportedHaptics: String { text(Key.errorUnsupportedHaptics) }

    public static func errorAnalysisFailed(detail: String) -> String {
        format(Key.errorAnalysisFailedFormat, localizedDetail(detail))
    }

    public static func errorGenerationFailed(detail: String) -> String {
        format(Key.errorGenerationFailedFormat, localizedDetail(detail))
    }

    public static func errorExportFailed(detail: String) -> String {
        format(Key.errorExportFailedFormat, localizedDetail(detail))
    }

    public static func errorPlaybackFailed(detail: String) -> String {
        format(Key.errorPlaybackFailedFormat, localizedDetail(detail))
    }

    public static func errorDetailPatternBuildFailed(detail: String) -> String {
        format(Key.errorDetailPatternBuildFailedFormat, detail)
    }

    public static func localizedDetail(_ detail: String) -> String {
        guard detail.hasPrefix("error.detail.") else {
            return detail
        }
        return text(detail)
    }

    public static func text(_ key: String) -> String {
        let bundle = resolvedBundle()
        let localized = bundle.localizedString(forKey: key, value: key, table: tableName)
        if localized != key {
            return localized
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: tableName)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments)
    }

    private static func format(_ key: String, arguments: [CVarArg]) -> String {
        String(format: text(key), locale: AppLanguage.persisted.locale, arguments: arguments)
    }

    private static func clampPercent(_ value: Float) -> Float {
        max(0, min(100, value * 100))
    }

    private static func resolvedBundle() -> Bundle {
        let language = AppLanguage.persisted
        guard let localizationIdentifier = language.localizationIdentifier else {
            return .main
        }

        guard let path = Bundle.main.path(forResource: localizationIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
