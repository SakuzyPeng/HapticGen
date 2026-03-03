import SwiftUI

@main
struct AudioHapticGeneratorApp: App {
    @State private var incomingZipURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView()
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
