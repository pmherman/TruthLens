import Foundation

/// Prepares reply text for text-to-speech: a voice shouldn't read out URLs, markdown marks or emoji names.
public enum SpokenText {
    public static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"https?://\S+"#, with: "link", options: .regularExpression)
        t = t.filter { !"*_`#>~".contains($0) }
        t = String(String.UnicodeScalarView(t.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x200D)
        }))
        // Keep line breaks (they become pauses), but tidy the spaces around them.
        return t.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
