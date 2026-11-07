import AppKit
import Foundation

/// A workspace's optional sidebar icon. Exactly one kind is set at a time:
/// an SF Symbol name, an emoji grapheme cluster, or a stored custom image file.
///
/// This is the in-memory representation. Persistence goes through
/// ``PersistedWorkspaceIcon`` so that snapshots written by a future build with
/// an unknown kind decode to `nil` instead of failing the whole workspace
/// restore.
enum WorkspaceIcon: Equatable, Hashable, Sendable {
    /// SF Symbol name (e.g. `"hammer.fill"`). Rendered template-style so it
    /// tints with the workspace color.
    case symbol(String)
    /// An emoji string (e.g. `"🔨"`).
    case emoji(String)
    /// Filename (not a full path) of a custom image inside the
    /// ``WorkspaceIconStore`` directory.
    case image(String)

    /// The trimmed payload for the active kind. Empty strings are treated as
    /// "no value" by ``sanitized``.
    var rawValue: String {
        switch self {
        case .symbol(let value), .emoji(let value), .image(let value):
            return value
        }
    }

    /// Returns a normalized copy, or `nil` when the payload is empty/whitespace
    /// (which should be treated as "no icon").
    var sanitized: WorkspaceIcon? {
        switch self {
        case .symbol(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .symbol(trimmed)
        case .emoji(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .emoji(trimmed)
        case .image(let value):
            // Only the base filename is ever stored; strip any directory
            // components defensively so a crafted snapshot can't point outside
            // the store directory.
            let base = (value as NSString).lastPathComponent
            return base.isEmpty ? nil : .image(base)
        }
    }
}

// MARK: - Persistence bridge

/// Codable representation of ``WorkspaceIcon`` used inside session snapshots.
/// Stored as a small `{ kind, value }` object so unrecognized kinds degrade to
/// "no icon" instead of throwing during decode.
struct PersistedWorkspaceIcon: Codable, Sendable, Equatable {
    var kind: String
    var value: String
}

extension WorkspaceIcon {
    private enum Kind {
        static let symbol = "symbol"
        static let emoji = "emoji"
        static let image = "image"
    }

    /// The on-disk representation for this icon.
    var persisted: PersistedWorkspaceIcon {
        switch self {
        case .symbol(let value):
            return PersistedWorkspaceIcon(kind: Kind.symbol, value: value)
        case .emoji(let value):
            return PersistedWorkspaceIcon(kind: Kind.emoji, value: value)
        case .image(let value):
            return PersistedWorkspaceIcon(kind: Kind.image, value: value)
        }
    }

    /// Reconstructs an icon from its persisted form. Returns `nil` for unknown
    /// kinds or empty payloads so callers can simply drop the icon.
    init?(persisted: PersistedWorkspaceIcon) {
        let icon: WorkspaceIcon
        switch persisted.kind {
        case Kind.symbol:
            icon = .symbol(persisted.value)
        case Kind.emoji:
            icon = .emoji(persisted.value)
        case Kind.image:
            icon = .image(persisted.value)
        default:
            return nil
        }
        guard let sanitized = icon.sanitized else { return nil }
        self = sanitized
    }
}

// MARK: - Custom image storage

/// Stores and resolves the custom images used by ``WorkspaceIcon/image(_:)``.
///
/// Images are downscaled to at most ``maxDimension`` points and written as PNG
/// into `<Application Support>/cmux/WorkspaceIcons/`. Only the resulting
/// filename is persisted in the session manifest, keeping snapshots portable
/// across machines and home-directory changes.
enum WorkspaceIconStore {
    /// Longest edge (in pixels) kept when importing a custom image.
    static let maxDimension: CGFloat = 128
    private static let directoryName = "WorkspaceIcons"

    @MainActor
    private static var imageCache: [String: NSImage] = [:]

    /// Resolves the store directory, optionally creating it.
    static func storeDirectoryURL(create: Bool = false) -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let directory = appSupport
            .appendingPathComponent("cmux", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }

    /// Absolute URL for a stored filename, or `nil` if the name is unusable.
    static func imageURL(forFilename filename: String) -> URL? {
        let safe = (filename as NSString).lastPathComponent
        guard !safe.isEmpty else { return nil }
        return storeDirectoryURL()?.appendingPathComponent(safe, isDirectory: false)
    }

    /// Imports an image from `sourceURL`, downscaling and re-encoding it as PNG.
    /// Returns the stored filename on success.
    @MainActor
    static func importImage(from sourceURL: URL) -> String? {
        guard let image = NSImage(contentsOf: sourceURL),
              let data = downscaledPNGData(from: image, maxDimension: maxDimension),
              let directory = storeDirectoryURL(create: true) else {
            return nil
        }
        let filename = "\(UUID().uuidString).png"
        let destination = directory.appendingPathComponent(filename, isDirectory: false)
        do {
            try data.write(to: destination, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    /// Copies an existing stored image to a new filename. Used when one image
    /// icon is applied to several workspaces so each owns its own file.
    @MainActor
    static func duplicateImage(filename: String) -> String? {
        guard let sourceURL = imageURL(forFilename: filename),
              FileManager.default.fileExists(atPath: sourceURL.path),
              let directory = storeDirectoryURL(create: true) else {
            return nil
        }
        let newFilename = "\(UUID().uuidString).png"
        let destination = directory.appendingPathComponent(newFilename, isDirectory: false)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return newFilename
        } catch {
            return nil
        }
    }

    /// Best-effort deletion of a stored image and its cache entry.
    @MainActor
    static func deleteImage(filename: String) {
        imageCache.removeValue(forKey: (filename as NSString).lastPathComponent)
        guard let url = imageURL(forFilename: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Loads a stored image, caching the result. Filenames are content-unique
    /// (a fresh UUID per import) so a cache keyed by filename never goes stale.
    @MainActor
    static func loadImage(filename: String) -> NSImage? {
        let safe = (filename as NSString).lastPathComponent
        guard !safe.isEmpty else { return nil }
        if let cached = imageCache[safe] {
            return cached
        }
        guard let url = imageURL(forFilename: safe),
              FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        imageCache[safe] = image
        return image
    }

    /// Downscales an image preserving aspect ratio and returns PNG data.
    @MainActor
    static func downscaledPNGData(from image: NSImage, maxDimension: CGFloat) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = NSSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()

        return rep.representation(using: .png, properties: [:])
    }
}
