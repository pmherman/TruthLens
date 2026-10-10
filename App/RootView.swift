import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            ScanView()
                .tabItem { Label("AI Scan", systemImage: "sparkle.magnifyingglass") }
            FactCheckView()
                .tabItem { Label("Fact Check", systemImage: "checkmark.seal") }
        }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .task { if !model.hasKey { model.showSettings = true } }
    }
}
