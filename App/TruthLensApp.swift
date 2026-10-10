import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct TruthLensApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About TruthLens") { showAbout() }
            }
        }
        #endif
    }

    #if os(macOS)
    /// The standard About panel, with the developer credit and links added.
    private func showAbout() {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.paragraphSpacing = 4
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]
        let credits = NSMutableAttributedString(
            string: "Developed by \(AppInfo.developer)\n", attributes: base)
        var link = base
        link[.link] = AppInfo.repoURL
        credits.append(NSAttributedString(string: "github.com/pmherman/TruthLens\n", attributes: link))
        var report = base
        report[.link] = AppInfo.repoURL.appendingPathComponent("issues")
        credits.append(NSAttributedString(string: "Report a bug", attributes: report))
        if !AppInfo.isTaggedRelease {
            credits.append(NSAttributedString(string: "\nUnreleased changes since v\(AppInfo.version)", attributes: base))
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    #endif
}
