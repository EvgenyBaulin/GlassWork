import CoreGraphics
import Foundation
import ImageIO

/// A photo ready for the shared container: already small, in two sizes.
public struct ReadPhoto: Sendable, Equatable {
    public var date: Date?
    public var name: String
    public var image: Data
    public var thumbnail: Data

    public init(date: Date?, name: String, image: Data, thumbnail: Data) {
        self.date = date
        self.name = name
        self.image = image
        self.thumbnail = thumbnail
    }

    /// Enough for the extra large size on a Retina screen, and small enough for WidgetKit's archives.
    public static let imagePixels = 900
    public static let thumbnailPixels = 240
}

public struct FolderReading: Sendable, Equatable {
    public var total: Int
    public var photos: [ReadPhoto]

    public init(total: Int, photos: [ReadPhoto]) {
        self.total = total
        self.photos = photos
    }
}

/// Reads the folder the user picked. Tests substitute their own.
public protocol PhotoFolderReading: Sendable {
    /// Nil when the folder cannot be read.
    func read(folder: URL, seed: UInt64, limit: Int) async -> FolderReading?
}

/// The Photos library. Tests substitute their own, so no test can bring up the macOS prompt.
public protocol PhotoLibraryReading: Sendable {
    /// Only looks. It never brings up a prompt.
    func access() -> PersonalAccess
    /// Brings up the macOS prompt: only a button may lead here.
    func requestAccess() async -> PersonalAccess
    /// Photos taken on this day in past years, newest first.
    func photos(onThisDay date: Date, limit: Int) async -> [ReadPhoto]
}

/// Contacts. Tests substitute their own, so no test can bring up the macOS prompt.
public protocol BirthdayReading: Sendable {
    /// Only looks. It never brings up a prompt.
    func access() -> PersonalAccess
    /// Brings up the macOS prompt: only a button may lead here.
    func requestAccess() async -> PersonalAccess
    func birthdays() async -> [ContactBirthday]
}

/// Stands in where the app has not provided the real one: it never has access.
public struct NoPersonalData: PhotoLibraryReading, BirthdayReading {
    public init() {}

    public func access() -> PersonalAccess {
        .denied
    }

    public func requestAccess() async -> PersonalAccess {
        .denied
    }

    public func photos(onThisDay _: Date, limit _: Int) async -> [ReadPhoto] {
        []
    }

    public func birthdays() async -> [ContactBirthday] {
        []
    }
}

/// Reads photos straight from a folder. The app has no sandbox, so a plain path is enough.
public struct PhotoFolderReader: PhotoFolderReading {
    private static let extensions: Set<String> = ["jpg", "jpeg", "heic", "png"]

    public init() {}

    public func read(folder: URL, seed: UInt64, limit: Int) async -> FolderReading? {
        let manager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let files = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: options
        ) else { return nil }
        let images = files
            .filter { Self.extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var photos: [ReadPhoto] = []
        for file in PhotoRotation.shuffled(images, seed: seed) where photos.count < limit {
            if let photo = Self.photo(at: file) {
                photos.append(photo)
            }
        }
        return FolderReading(total: images.count, photos: photos)
    }

    private static func photo(at file: URL) -> ReadPhoto? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = ArtworkImage.fitted(source, pixels: ReadPhoto.imagePixels),
              let thumbnail = ArtworkImage.fitted(source, pixels: ReadPhoto.thumbnailPixels) else { return nil }
        let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate
        return ReadPhoto(
            date: exifDate(source) ?? created,
            name: file.deletingPathExtension().lastPathComponent,
            image: image,
            thumbnail: thumbnail
        )
    }

    private static func exifDate(_ source: CGImageSource) -> Date? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        return (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(parseExifDate)
    }

    /// EXIF writes dates as `2025:08:14 19:42:03`, in the camera's local time.
    public static func parseExifDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
