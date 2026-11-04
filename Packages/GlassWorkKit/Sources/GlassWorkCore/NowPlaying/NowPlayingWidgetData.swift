import CoreGraphics
import Foundation
import ImageIO

/// What the Now Playing and Lyrics widgets show.
public struct NowPlayingWidgetData: Codable, Sendable, Equatable {
    public var session: NowPlayingSession
    public var artwork: Data?
    public var outputDevice: String?

    public init(session: NowPlayingSession, artwork: Data? = nil, outputDevice: String? = nil) {
        self.session = session
        self.artwork = artwork
        self.outputDevice = outputDevice
    }
}

/// Keeps artwork small enough for the shared container and for WidgetKit's archives.
public enum ArtworkImage {
    /// Twice the largest size a widget draws it at.
    public static let pixels = 360
    private static let quality = 0.8

    /// A JPEG no bigger than `pixels` on its long side, or nil for data that is not an image.
    public static func fitted(_ data: Data, pixels: Int = pixels) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// The session and its artwork in the shared container, apart from the main snapshot:
/// they change with every track, and the artwork is only written when it changes.
public struct NowPlayingSnapshots: Sendable {
    public static let sessionKey = "nowPlaying"
    public static let artworkKey = "nowPlayingArtwork"

    private struct Record: Codable {
        var session: NowPlayingSession?
        var outputDevice: String?
    }

    private let store: SnapshotStore

    public init(store: SnapshotStore = SnapshotStore()) {
        self.store = store
    }

    /// Writes what changed. An idle session clears the record, so widgets go back to their empty look.
    public func write(_ data: NowPlayingWidgetData?) throws {
        try store.write(Record(session: data?.session, outputDevice: data?.outputDevice), for: Self.sessionKey)
        if let artwork = data?.artwork, artwork != store.readData(for: Self.artworkKey) {
            try store.writeData(artwork, for: Self.artworkKey)
        }
    }

    public func read() -> NowPlayingWidgetData? {
        guard let record = store.read(Record.self, for: Self.sessionKey), let session = record.session else {
            return nil
        }
        let artwork = session.artworkID == nil ? nil : store.readData(for: Self.artworkKey)
        return NowPlayingWidgetData(session: session, artwork: artwork, outputDevice: record.outputDevice)
    }
}

/// A transport button pressed in a WidgetKit widget, on its way to the app.
///
/// The extension is sandboxed and cannot reach the adapter, so it leaves the command
/// in the shared container and posts a Darwin notification.
public struct NowPlayingRequest: Codable, Sendable, Equatable {
    public var command: NowPlayingCommand
    public var date: Date

    public init(command: NowPlayingCommand, date: Date = Date()) {
        self.command = command
        self.date = date
    }

    public static let key = "nowPlayingRequest"
    private static let lifetime: TimeInterval = 10

    public static var notificationName: String {
        "\(AppGroup.identifier ?? "io.github.evgenybaulin.glasswork").nowPlayingRequest"
    }

    /// A request left over from before the app started is not acted on.
    public func isFresh(at date: Date) -> Bool {
        abs(date.timeIntervalSince(self.date)) < Self.lifetime
    }
}

/// Limits WidgetKit reloads, which macOS rations. Changes in between collapse into one trailing reload.
public struct ReloadThrottle: Sendable {
    public var interval: TimeInterval
    private var last = Date.distantPast

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// How long to wait before reloading; zero means now.
    public mutating func delay(at date: Date) -> TimeInterval {
        let wait = last.addingTimeInterval(interval).timeIntervalSince(date)
        guard wait > 0 else {
            last = date
            return 0
        }
        return wait
    }

    public mutating func didReload(at date: Date) {
        last = date
    }
}
