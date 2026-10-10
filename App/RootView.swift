import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            ScanView()
                .tabItem { Label("AI Scan", systemImage: "sparkle.magnifyingglass") }
                .tag(AppTab.scan)
            FactCheckView()
                .tabItem { Label("Fact Check", systemImage: "checkmark.seal") }
                .tag(AppTab.factCheck)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.stats)
        }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .task { if !model.hasKey { model.showSettings = true } }
    }
}
