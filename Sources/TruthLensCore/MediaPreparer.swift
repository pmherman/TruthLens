import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

public struct PreparedMedia: Sendable {
    public let kind: MediaKind
    /// JPEG frames ready to send to the model (empty for audio).
    public let frames: [Data]
    public let signals: [MetadataSignal]
}

public enum MediaError: LocalizedError {
    case unreadable, unsupported
    public var errorDescription: String? {
        switch self {
        case .unreadable: "That file couldn't be read."
        case .unsupported: "That file type isn't supported."
        }
    }
}

public enum MediaPreparer {
    public static func kind(for url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    public static func prepare(url: URL) async throws -> PreparedMedia {
        guard let kind = kind(for: url) else { throw MediaError.unsupported }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw MediaError.unreadable }
        return try await prepare(data: data, kind: kind, url: url)
    }

    public static func prepare(data: Data, kind: MediaKind, url: URL? = nil) async throws -> PreparedMedia {
        // Metadata first: re-encoding for the model would destroy it.
        let signals = MetadataAnalyzer.analyze(data, kind: kind)
        switch kind {
        case .image:
            guard let jpeg = downscaledJPEG(from: data) else { throw MediaError.unreadable }
            return PreparedMedia(kind: .image, frames: [jpeg], signals: signals)
        case .video:
            guard let url else { throw MediaError.unreadable }
            return PreparedMedia(kind: .video, frames: try await videoFrames(url: url), signals: signals)
        case .audio:
            return PreparedMedia(kind: .audio, frames: [], signals: signals)
        }
    }

    static func downscaledJPEG(from data: Data, maxPixel: Int = 1568) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return jpeg(cg)
    }

    /// A small, lower-quality JPEG for history thumbnails.
    public static func thumbnail(from data: Data, maxPixel: Int, quality: Double = 0.6) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return jpeg(cg, quality: quality)
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func videoFrames(url: URL, count: Int = 5) async throws -> [Data] {
        let asset = AVURLAsset(url: url)
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0 else { throw MediaError.unreadable }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1280, height: 1280)
        var frames: [Data] = []
        for i in 0..<count {
            let t = CMTime(seconds: seconds * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
            if let cg = try? await gen.image(at: t).image, let data = jpeg(cg) { frames.append(data) }
        }
        guard !frames.isEmpty else { throw MediaError.unreadable }
        return frames
    }
}
