import SwiftUI

@main
struct TruthLensApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
    }
}
