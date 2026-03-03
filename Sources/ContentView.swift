import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TimelineEditorView()
                .tabItem {
                    Label("Editor", systemImage: "waveform.path.ecg")
                }

            DebugDashboardView()
                .tabItem {
                    Label("Debug", systemImage: "ladybug")
                }
        }
    }
}
