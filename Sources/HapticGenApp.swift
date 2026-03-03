import SwiftUI

@main
struct HapticGenApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageOverrideRawValue: String = AppLanguage.auto.rawValue
    @State private var incomingZipURL: URL?

    private var selectedLanguage: AppLanguage {
        AppLanguage.resolved(rawValue: languageOverrideRawValue)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, selectedLanguage.locale)
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "zip" else { return }
                    incomingZipURL = url
                }
                .sheet(item: $incomingZipURL) { url in
                    HapticTrailerPlayerView(zipURL: url)
                }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
