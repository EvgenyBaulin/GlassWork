import Foundation
import Observation

/// Reads the user's own photos and contacts for their widgets, in the host app only.
///
/// Reading happens at most once a day per widget, and only for a widget that is on. Nothing here asks macOS for
/// anything except `requestPhotos` and `requestContacts`, which only a button may call.
@MainActor
@Observable
public final class PersonalWidgetStore {
    public private(set) var data = PersonalWidgetData()
    /// What macOS allows now, for the Settings section.
    public private(set) var photosAccess: PersonalAccess
    public private(set) var contactsAccess: PersonalAccess

    public nonisolated static let photoLimit = 24
    public nonisolated static let onThisDayLimit = 12
    public nonisolated static let birthdayLimit = 12

    @ObservationIgnored private let folder: any PhotoFolderReading
    @ObservationIgnored private let library: any PhotoLibraryReading
    @ObservationIgnored private let contacts: any BirthdayReading
    @ObservationIgnored private let images: SnapshotStore
    /// When each widget was last read, with the folder it read.
    @ObservationIgnored private var lastRead: [WidgetKind: String] = [:]

    public init(
        folder: any PhotoFolderReading = PhotoFolderReader(),
        library: any PhotoLibraryReading = NoPersonalData(),
        contacts: any BirthdayReading = NoPersonalData(),
        images: SnapshotStore = SnapshotStore()
    ) {
        self.folder = folder
        self.library = library
        self.contacts = contacts
        self.images = images
        photosAccess = library.access()
        contactsAccess = contacts.access()
    }

    /// Brings up the macOS prompt. Only the button in Settings calls this.
    public func requestPhotos() async -> PersonalAccess {
        photosAccess = await library.requestAccess()
        return photosAccess
    }

    /// Brings up the macOS prompt. Only the button in Settings calls this.
    public func requestContacts() async -> PersonalAccess {
        contactsAccess = await contacts.requestAccess()
        return contactsAccess
    }

    /// Brings what `kinds` show up to date. A widget turned off loses what it had, whether placed or not.
    public func refresh(
        _ settings: PersonalWidgetSettings,
        for kinds: Set<WidgetKind>,
        at date: Date = Date(),
        force: Bool = false
    ) async {
        photosAccess = library.access()
        contactsAccess = contacts.access()
        await refreshPhotoFrame(settings, isWanted: kinds.contains(.photoFrame), at: date, force: force)
        await refreshOnThisDay(settings, isWanted: kinds.contains(.onThisDay), at: date, force: force)
        await refreshBirthdays(settings, isWanted: kinds.contains(.birthdays), at: date, force: force)
    }

    private func isDue(_ kind: WidgetKind, _ mark: String, force: Bool) -> Bool {
        guard force || lastRead[kind] != mark else { return false }
        lastRead[kind] = mark
        return true
    }

    private func dayMark(_ date: Date) -> String {
        ScreenTimeLog.dayKey(date)
    }

    private func refreshPhotoFrame(
        _ settings: PersonalWidgetSettings,
        isWanted: Bool,
        at date: Date,
        force: Bool
    ) async {
        guard settings.isPhotoFrameOn, !settings.photoFolderPath.isEmpty else {
            clearPhotoFrame()
            return
        }
        guard isWanted, isDue(.photoFrame, "\(dayMark(date)) \(settings.photoFolderPath)", force: force) else { return }
        let url = URL(filePath: settings.photoFolderPath, directoryHint: .isDirectory)
        let folder = folder
        let seed = PhotoRotation.daySeed(date)
        let reading = await Task.detached(priority: .utility) {
            await folder.read(folder: url, seed: seed, limit: Self.photoLimit)
        }.value
        var result = PhotoFrameData()
        result.folderName = url.lastPathComponent
        if let reading {
            result.state = .ready
            result.total = reading.total
            result.photos = save(reading.photos, prefix: "photoFrame")
        } else {
            result.state = .unreadable
        }
        removeImages(prefix: "photoFrame", from: result.photos.count, limit: Self.photoLimit)
        data.photoFrame = result
    }

    private func clearPhotoFrame() {
        guard data.photoFrame != PhotoFrameData() else { return }
        data.photoFrame = PhotoFrameData()
        removeImages(prefix: "photoFrame", from: 0, limit: Self.photoLimit)
        lastRead[.photoFrame] = nil
    }

    private func refreshOnThisDay(
        _ settings: PersonalWidgetSettings,
        isWanted: Bool,
        at date: Date,
        force: Bool
    ) async {
        guard settings.isOnThisDayOn else {
            clearOnThisDay()
            return
        }
        guard photosAccess == .granted else {
            clearOnThisDay()
            data.onThisDay.state = .noAccess
            return
        }
        guard isWanted, isDue(.onThisDay, dayMark(date), force: force) else { return }
        let library = library
        let photos = await Task.detached(priority: .utility) {
            await library.photos(onThisDay: date, limit: Self.onThisDayLimit)
        }.value
        var result = OnThisDayData()
        result.state = .ready
        result.photos = save(photos, prefix: "onThisDay")
        removeImages(prefix: "onThisDay", from: result.photos.count, limit: Self.onThisDayLimit)
        data.onThisDay = result
    }

    private func clearOnThisDay() {
        guard data.onThisDay != OnThisDayData() else { return }
        data.onThisDay = OnThisDayData()
        removeImages(prefix: "onThisDay", from: 0, limit: Self.onThisDayLimit)
        lastRead[.onThisDay] = nil
    }

    private func refreshBirthdays(
        _ settings: PersonalWidgetSettings,
        isWanted: Bool,
        at date: Date,
        force: Bool
    ) async {
        guard settings.isBirthdaysOn else {
            data.birthdays = BirthdaysData()
            lastRead[.birthdays] = nil
            return
        }
        guard contactsAccess == .granted else {
            data.birthdays = BirthdaysData()
            data.birthdays.state = .noAccess
            lastRead[.birthdays] = nil
            return
        }
        guard isWanted, isDue(.birthdays, dayMark(date), force: force) else { return }
        let contacts = contacts
        let everyone = await Task.detached(priority: .utility) { await contacts.birthdays() }.value
        var result = BirthdaysData()
        result.state = .ready
        result.people = BirthdayPlanner.upcoming(everyone, at: date, limit: Self.birthdayLimit)
        result.total = everyone.count
        data.birthdays = result
    }

    /// Files are numbered, so tomorrow's photos replace today's instead of piling up.
    private func save(_ photos: [ReadPhoto], prefix: String) -> [WidgetPhoto] {
        photos.enumerated().compactMap { index, photo in
            let item = WidgetPhoto(id: "\(prefix)-\(index)", date: photo.date, name: photo.name)
            do {
                try images.writeData(photo.image, for: item.id)
                try images.writeData(photo.thumbnail, for: item.thumbnailID)
                return item
            } catch {
                return nil
            }
        }
    }

    private func removeImages(prefix: String, from start: Int, limit: Int) {
        for index in start ..< max(start, limit) {
            images.removeData(for: "\(prefix)-\(index)")
            images.removeData(for: "\(prefix)-\(index)-thumb")
        }
    }
}
