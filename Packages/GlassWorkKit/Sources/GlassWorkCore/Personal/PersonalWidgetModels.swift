import Foundation

/// What macOS says about the Photos library or Contacts.
public enum PersonalAccess: String, Codable, Sendable {
    case notAsked, granted, denied
}

/// The widgets that show the user's own photos and contacts. Each stays off until a button in Settings turns it on.
///
/// Nothing here is optional: saving overlays the new JSON on the old file, so a key that disappears from the encoded
/// value would keep its old content.
public struct PersonalWidgetSettings: Codable, Sendable, Equatable {
    public var isPhotoFrameOn = false
    /// Empty until the user picks a folder.
    public var photoFolderPath = ""
    public var isOnThisDayOn = false
    public var isBirthdaysOn = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case isPhotoFrameOn, photoFolderPath, isOnThisDayOn, isBirthdaysOn
    }

    /// One bad hand edit falls back to "off", which is the safe reading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPhotoFrameOn = (try? container.decodeIfPresent(Bool.self, forKey: .isPhotoFrameOn)) ?? false
        photoFolderPath = (try? container.decodeIfPresent(String.self, forKey: .photoFolderPath)) ?? ""
        isOnThisDayOn = (try? container.decodeIfPresent(Bool.self, forKey: .isOnThisDayOn)) ?? false
        isBirthdaysOn = (try? container.decodeIfPresent(Bool.self, forKey: .isBirthdaysOn)) ?? false
    }
}

public enum PersonalWidgetState: String, Codable, Sendable {
    /// Turned off, so nothing was read.
    case off
    /// On, but macOS does not allow it any more.
    case noAccess
    /// The chosen folder is gone or cannot be read.
    case unreadable
    case ready
}

/// One photo a widget can show. Its image lives in the shared container under `id`.
public struct WidgetPhoto: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var date: Date?
    public var name: String

    public init(id: String, date: Date?, name: String) {
        self.id = id
        self.date = date
        self.name = name
    }

    /// The small copy for strips and grids.
    public var thumbnailID: String {
        "\(id)-thumb"
    }
}

public struct PhotoFrameData: Codable, Sendable, Equatable {
    public var state = PersonalWidgetState.off
    public var folderName = ""
    /// Photos in the folder; `photos` holds today's selection of them.
    public var total = 0
    public var photos: [WidgetPhoto] = []

    public init() {}
}

public struct OnThisDayData: Codable, Sendable, Equatable {
    public var state = PersonalWidgetState.off
    /// Newest year first.
    public var photos: [WidgetPhoto] = []

    public init() {}
}

/// A person with a birthday coming up. Only the name and the day leave the app's own memory.
public struct WidgetBirthday: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// The next time it comes round, at the start of that day.
    public var date: Date
    /// Nil when the contact has no birth year.
    public var turns: Int?

    public init(id: String, name: String, date: Date, turns: Int?) {
        self.id = id
        self.name = name
        self.date = date
        self.turns = turns
    }

    /// Up to two letters for the avatar.
    public var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

public struct BirthdaysData: Codable, Sendable, Equatable {
    public var state = PersonalWidgetState.off
    /// Soonest first.
    public var people: [WidgetBirthday] = []
    /// Everyone with a birthday, including those not listed.
    public var total = 0

    public init() {}
}

/// Everything these widgets show except the images, which are too large for the shared snapshot.
public struct PersonalWidgetData: Codable, Sendable, Equatable {
    public var photoFrame = PhotoFrameData()
    public var onThisDay = OnThisDayData()
    public var birthdays = BirthdaysData()

    public init() {}
}

public extension WidgetKind {
    /// These read the user's own photos or contacts.
    static let personalKinds: Set<WidgetKind> = [.photoFrame, .onThisDay, .birthdays]
}

/// Which photos a size draws at one moment, so the extension loads only those.
public extension [WidgetPhoto] {
    /// The photo on show, then what follows it.
    func rotated(by index: Int) -> [WidgetPhoto] {
        guard !isEmpty else { return [] }
        let start = index % count
        return Array(self[start...] + self[..<start])
    }

    func imageKeys(at index: Int, size: WidgetSize) -> [String] {
        let shown = rotated(by: index)
        guard let first = shown.first else { return [] }
        let thumbnails = switch size {
        case .small, .medium: 0
        case .large: 5
        case .extraLarge: 9
        }
        return [first.id] + shown.dropFirst().prefix(thumbnails).map(\.thumbnailID)
    }
}
