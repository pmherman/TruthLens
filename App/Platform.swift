import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension Image {
    init?(data: Data) {
        #if canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        self.init(uiImage: img)
        #else
        guard let img = NSImage(data: data) else { return nil }
        self.init(nsImage: img)
        #endif
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Image on the pasteboard, if any, as PNG/TIFF data.
    static func imageData() -> Data? {
        #if canImport(UIKit)
        return UIPasteboard.general.image?.pngData()
        #else
        return NSPasteboard.general.data(forType: .png) ?? NSPasteboard.general.data(forType: .tiff)
        #endif
    }
}

extension Color {
    static var cardFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
