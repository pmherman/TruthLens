import Foundation
import ImageIO

/// On-device forensic checks that run before (and independently of) any model call.
public struct MetadataSignal: Hashable, Sendable {
    public enum Strength: Sendable { case strongAI, weakAI, neutral, weakAuthentic, strongAuthentic }
    public let label: String
    public let detail: String
    public let strength: Strength
}

public enum MetadataAnalyzer {
    /// Strings that generators and standards embed in files.
    static let aiFingerprints: [(needle: String, name: String)] = [
        ("trainedAlgorithmicMedia", "IPTC digital source type: trained algorithmic media"),
        ("compositeWithTrainedAlgorithmicMedia", "IPTC digital source type: composite with AI media"),
        ("algorithmicMedia", "IPTC digital source type: algorithmic media"),
        ("Midjourney", "Midjourney"),
        ("DALL-E", "DALL·E"), ("DALL·E", "DALL·E"),
        ("Stable Diffusion", "Stable Diffusion"),
        ("Adobe Firefly", "Adobe Firefly"),
        ("Imagen", "Google Imagen"),
        ("SynthID", "Google SynthID"),
        ("Sora", "OpenAI Sora"),
        ("ComfyUI", "ComfyUI"),
        ("NovelAI", "NovelAI"),
        ("Flux", "Flux"),
        ("ElevenLabs", "ElevenLabs voice synthesis"),
        ("Suno", "Suno music generation"),
        ("Udio", "Udio music generation"),
    ]

    public static func analyze(_ data: Data, kind: MediaKind) -> [MetadataSignal] {
        var signals: [MetadataSignal] = []
        let scan = data.prefix(16_000_000)

        // C2PA / Content Credentials manifest (JUMBF box labelled "c2pa").
        let hasC2PA = scan.range(of: Data("c2pa".utf8)) != nil && scan.range(of: Data("jumb".utf8)) != nil
        if hasC2PA {
            signals.append(.init(label: "Content Credentials (C2PA) present",
                                 detail: "The file carries a signed provenance manifest. Verify the signer to see who made or edited it.",
                                 strength: .neutral))
        }

        var seen = Set<String>()
        for (needle, name) in aiFingerprints where scan.range(of: Data(needle.utf8)) != nil {
            // Short generic words are only trusted when a manifest or XMP packet is also present.
            // Compressed data can contain short words by chance, so require a metadata container too.
            let generic = needle.count <= 6
            if generic && !hasC2PA && scan.range(of: Data("<x:xmpmeta".utf8)) == nil
                && scan.range(of: Data("ID3".utf8)) == nil { continue }
            guard seen.insert(name).inserted else { continue }
            signals.append(.init(label: "AI marker found: \(name)",
                                 detail: "This string is embedded in the file's metadata, which generators use to label their output.",
                                 strength: .strongAI))
        }

        if kind == .image { signals += imageSignals(data) }
        if signals.isEmpty {
            signals.append(.init(label: "No provenance metadata",
                                 detail: "No AI markers or credentials found. Social platforms strip metadata, so this alone proves nothing.",
                                 strength: .neutral))
        }
        return signals
    }

    static func imageSignals(_ data: Data) -> [MetadataSignal] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return [] }
        var out: [MetadataSignal] = []

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let png = props[kCGImagePropertyPNGDictionary] as? [String: Any] ?? [:]

        if let make = tiff[kCGImagePropertyTIFFMake] as? String,
           let model = tiff[kCGImagePropertyTIFFModel] as? String {
            var detail = "Shot on \(make) \(model)."
            if exif[kCGImagePropertyExifFNumber] != nil || exif[kCGImagePropertyExifExposureTime] != nil {
                detail += " Lens and exposure data are present."
            }
            out.append(.init(label: "Camera EXIF present", detail: detail, strength: .weakAuthentic))
        }
        if let software = tiff[kCGImagePropertyTIFFSoftware] as? String {
            out.append(.init(label: "Software tag: \(software)",
                             detail: "The file was written or edited by this software.", strength: .neutral))
        }
        if png["parameters"] != nil {
            out.append(.init(label: "Generation parameters in PNG",
                             detail: "A prompt/parameters text chunk is embedded, typical of Stable Diffusion tools.",
                             strength: .strongAI))
        }
        return out
    }

    /// Collapses signals into a prior the model is told about (not a final answer).
    public static func summary(_ signals: [MetadataSignal]) -> String {
        signals.map { s in
            let tag: String
            switch s.strength {
            case .strongAI: tag = "STRONG-AI"
            case .weakAI: tag = "weak-AI"
            case .neutral: tag = "neutral"
            case .weakAuthentic: tag = "weak-authentic"
            case .strongAuthentic: tag = "STRONG-authentic"
            }
            return "- [\(tag)] \(s.label): \(s.detail)"
        }.joined(separator: "\n")
    }
}
