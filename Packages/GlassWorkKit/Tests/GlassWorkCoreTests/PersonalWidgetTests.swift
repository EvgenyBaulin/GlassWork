import CoreGraphics
import Foundation
@testable import GlassWorkCore
import ImageIO
import Testing

private func gregorian(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
    return calendar
}

private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    gregorian().date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
}

struct BirthdayPlannerTests {
    private let calendar = gregorian()

    private func next(_ month: Int, _ dayOfMonth: Int, at date: Date) -> Date? {
        let birthday = ContactBirthday(id: "1", name: "Anna", month: month, day: dayOfMonth)
        return BirthdayPlanner.next(birthday, onOrAfter: date, calendar: calendar)
    }

    @Test func todayCountsAsToday() {
        #expect(next(11, 5, at: day(2026, 11, 5, hour: 23)) == day(2026, 11, 5, hour: 0))
    }

    @Test func aDayThatPassedMovesToNextYear() {
        #expect(next(11, 4, at: day(2026, 11, 5)) == day(2027, 11, 4, hour: 0))
    }

    @Test func theYearWrapsFromDecemberToJanuary() {
        #expect(next(1, 2, at: day(2026, 12, 31)) == day(2027, 1, 2, hour: 0))
    }

    @Test func aLeapDayFallsOnTheLastDayOfFebruaryInOtherYears() {
        #expect(next(2, 29, at: day(2026, 1, 10)) == day(2026, 2, 28, hour: 0))
    }

    @Test func aLeapDayStaysOnItsDayInLeapYears() {
        #expect(next(2, 29, at: day(2028, 1, 10)) == day(2028, 2, 29, hour: 0))
    }

    @Test func aDateThatDoesNotExistIsDropped() {
        #expect(next(4, 31, at: day(2026, 1, 10)) == nil)
    }

    @Test func theAgeIsWhatTheyTurnNotWhatTheyAre() {
        let list = [ContactBirthday(id: "1", name: "Anna", month: 11, day: 5, year: 1996)]
        let person = BirthdayPlanner.upcoming(list, at: day(2026, 11, 2), limit: 5, calendar: calendar)
        #expect(person.first?.turns == 30)
    }

    @Test func noBirthYearMeansNoAge() {
        let list = [ContactBirthday(id: "1", name: "Dad", month: 12, day: 3)]
        let person = BirthdayPlanner.upcoming(list, at: day(2026, 11, 2), limit: 5, calendar: calendar)
        #expect(person.first?.turns == nil)
    }

    @Test func aYearAfterTheBirthdayIsNotAnAge() {
        let list = [ContactBirthday(id: "1", name: "Dad", month: 12, day: 3, year: 2030)]
        let person = BirthdayPlanner.upcoming(list, at: day(2026, 11, 2), limit: 5, calendar: calendar)
        #expect(person.first?.turns == nil)
    }

    @Test func soonestComesFirstThenTheName() {
        let list = [
            ContactBirthday(id: "1", name: "Mark", month: 1, day: 1),
            ContactBirthday(id: "2", name: "Zoe", month: 11, day: 5),
            ContactBirthday(id: "3", name: "Anna", month: 11, day: 5),
        ]
        let people = BirthdayPlanner.upcoming(list, at: day(2026, 11, 2), limit: 2, calendar: calendar)
        #expect(people.map(\.name) == ["Anna", "Zoe"])
    }

    @Test func daysUntilIgnoresTheHour() {
        let person = WidgetBirthday(id: "1", name: "A", date: day(2026, 11, 5, hour: 0), turns: nil)
        #expect(BirthdayPlanner.daysUntil(person, from: day(2026, 11, 2, hour: 23), calendar: calendar) == 3)
        #expect(BirthdayPlanner.daysUntil(person, from: day(2026, 11, 5, hour: 23), calendar: calendar) == 0)
    }

    @Test func aLunarDateWithAYearIsConverted() throws {
        let chinese = Calendar(identifier: .chinese)
        let source = chinese.dateComponents(in: chinese.timeZone, from: day(2000, 6, 15))
        var parts = DateComponents(calendar: chinese, era: source.era, year: source.year)
        parts.month = source.month
        parts.day = source.day
        let birthday = try #require(ContactBirthday(id: "1", name: "A", components: parts))
        #expect(birthday.month == 6)
        #expect(birthday.year == 2000)
    }

    @Test func aLunarDateWithoutAYearCannotBePlaced() {
        var parts = DateComponents(calendar: Calendar(identifier: .chinese))
        parts.month = 3
        parts.day = 5
        #expect(ContactBirthday(id: "1", name: "A", components: parts) == nil)
    }

    @Test func gregorianComponentsPassThrough() {
        var parts = DateComponents(calendar: calendar)
        parts.month = 3
        parts.day = 5
        #expect(ContactBirthday(id: "1", name: "A", components: parts)?.month == 3)
    }

    @Test(arguments: [(13, 1), (0, 1), (1, 32), (1, 0)])
    func nonsenseIsRefused(month: Int, dayOfMonth: Int) {
        let parts = DateComponents(month: month, day: dayOfMonth)
        #expect(ContactBirthday(id: "1", name: "A", components: parts) == nil)
    }

    @Test func initialsTakeTwoWords() {
        let date = Date()
        #expect(WidgetBirthday(id: "1", name: "anna petrova ivanovna", date: date, turns: nil).initials == "AP")
        #expect(WidgetBirthday(id: "1", name: "Dad", date: date, turns: nil).initials == "D")
    }
}

struct OnThisDayTests {
    private let calendar = gregorian()

    @Test func coversPastYearsOnly() {
        let days = OnThisDay.days(before: day(2026, 11, 5), calendar: calendar)
        #expect(days.count == OnThisDay.yearsBack)
        #expect(days.first?.start == day(2025, 11, 5, hour: 0))
        #expect(days.allSatisfy { $0.end <= day(2026, 1, 1, hour: 0) })
    }

    @Test func aLeapDayLooksOnlyAtLeapYears() {
        let days = OnThisDay.days(before: day(2028, 2, 29), calendar: calendar)
        #expect(days.first?.start == day(2024, 2, 29, hour: 0))
        #expect(days.count == 7)
    }

    @Test func theLastDayOfFebruaryIncludesLeapDays() {
        let days = OnThisDay.days(before: day(2026, 2, 28), calendar: calendar)
        #expect(days.contains { $0.start == day(2024, 2, 29, hour: 0) })
        #expect(days.contains { $0.start == day(2025, 2, 28, hour: 0) })
    }

    @Test func yearsAgoCountsCalendarYears() {
        #expect(OnThisDay.yearsAgo(day(2023, 11, 5), from: day(2026, 11, 5), calendar: calendar) == 3)
    }
}

struct PhotoRotationTests {
    @Test func theIndexChangesOnceAQuarterOfAnHour() {
        let start = Date(timeIntervalSince1970: 900 * 100)
        let first = PhotoRotation.index(at: start, count: 7)
        #expect(PhotoRotation.index(at: start.addingTimeInterval(899), count: 7) == first)
        #expect(PhotoRotation.index(at: start.addingTimeInterval(900), count: 7) == (first + 1) % 7)
    }

    @Test func noPhotosAreNoProblem() {
        #expect(PhotoRotation.index(at: Date(), count: 0) == 0)
        #expect([WidgetPhoto]().rotated(by: 3).isEmpty)
        #expect([WidgetPhoto]().imageKeys(at: 3, size: .large).isEmpty)
    }

    @Test func theSameDayGivesTheSameOrder() {
        let items = Array(0 ..< 50)
        #expect(PhotoRotation.shuffled(items, seed: 20_261_105) == PhotoRotation.shuffled(items, seed: 20_261_105))
        #expect(PhotoRotation.shuffled(items, seed: 20_261_105) != PhotoRotation.shuffled(items, seed: 20_261_106))
        #expect(PhotoRotation.shuffled(items, seed: 5).sorted() == items)
    }

    @Test func aDayHasItsOwnSeed() {
        let calendar = gregorian()
        #expect(PhotoRotation.daySeed(day(2026, 11, 5), calendar: calendar) == 20_261_105)
    }

    @Test(arguments: [(WidgetSize.small, 1), (.medium, 1), (.large, 6), (.extraLarge, 10)])
    func eachSizeLoadsOnlyWhatItDraws(size: WidgetSize, count: Int) {
        let photos = (0 ..< 20).map { WidgetPhoto(id: "p\($0)", date: nil, name: "") }
        let keys = photos.imageKeys(at: 18, size: size)
        #expect(keys.count == count)
        #expect(keys.first == "p18")
        #expect(keys.dropFirst().allSatisfy { $0.hasSuffix("-thumb") })
    }

    @Test func exifDatesAreRead() {
        let date = PhotoFolderReader.parseExifDate("2025:08:14 19:42:03")
        #expect(date != nil)
        #expect(PhotoFolderReader.parseExifDate("yesterday") == nil)
    }
}

private final class Counter: @unchecked Sendable {
    // Tests are the only writers and they await every call, so no two touch this at once.
    var requests = 0
    var reads = 0
}

private struct FakeLibrary: PhotoLibraryReading {
    var state: PersonalAccess = .notAsked
    var afterRequest: PersonalAccess = .granted
    let counter: Counter

    func access() -> PersonalAccess {
        state
    }

    func requestAccess() async -> PersonalAccess {
        counter.requests += 1
        return afterRequest
    }

    func photos(onThisDay _: Date, limit _: Int) async -> [ReadPhoto] {
        counter.reads += 1
        return [ReadPhoto(date: nil, name: "", image: Data([1]), thumbnail: Data([2]))]
    }
}

private struct FakeContacts: BirthdayReading {
    var state: PersonalAccess = .notAsked
    var afterRequest: PersonalAccess = .granted
    let counter: Counter

    func access() -> PersonalAccess {
        state
    }

    func requestAccess() async -> PersonalAccess {
        counter.requests += 1
        return afterRequest
    }

    func birthdays() async -> [ContactBirthday] {
        counter.reads += 1
        return [ContactBirthday(id: "1", name: "Anna Petrova", month: 11, day: 5, year: 1996)]
    }
}

private struct FakeFolder: PhotoFolderReading {
    var reading: FolderReading?
    let counter: Counter

    func read(folder _: URL, seed _: UInt64, limit _: Int) async -> FolderReading? {
        counter.reads += 1
        return reading
    }
}

@MainActor
struct PersonalWidgetStoreTests {
    private let images = SnapshotStore(directory: temporaryFolder())
    private let counter = Counter()

    private func store(
        library: PersonalAccess = .notAsked,
        contacts: PersonalAccess = .notAsked,
        folder: FolderReading? = nil
    ) -> PersonalWidgetStore {
        PersonalWidgetStore(
            folder: FakeFolder(reading: folder, counter: counter),
            library: FakeLibrary(state: library, counter: counter),
            contacts: FakeContacts(state: contacts, counter: counter),
            images: images
        )
    }

    private var everything: Set<WidgetKind> {
        WidgetKind.personalKinds
    }

    private var allOn: PersonalWidgetSettings {
        var settings = PersonalWidgetSettings()
        settings.isPhotoFrameOn = true
        settings.photoFolderPath = "/tmp/Travel 2025"
        settings.isOnThisDayOn = true
        settings.isBirthdaysOn = true
        return settings
    }

    private let oneFolderPhoto = FolderReading(
        total: 48,
        photos: [ReadPhoto(date: nil, name: "IMG_2041", image: Data([9]), thumbnail: Data([8]))]
    )

    @Test func nothingIsReadOrAskedWhileOff() async {
        let store = store(library: .granted, contacts: .granted, folder: oneFolderPhoto)
        await store.refresh(PersonalWidgetSettings(), for: everything, at: day(2026, 11, 5), force: true)
        #expect(counter.reads == 0)
        #expect(counter.requests == 0)
        #expect(store.data == PersonalWidgetData())
    }

    @Test func refreshingNeverBringsUpAPrompt() async {
        let store = store(library: .notAsked, contacts: .notAsked)
        await store.refresh(allOn, for: everything, at: day(2026, 11, 5), force: true)
        #expect(counter.requests == 0)
        #expect(store.data.onThisDay.state == .noAccess)
        #expect(store.data.birthdays.state == .noAccess)
    }

    @Test func onlyTheButtonAsks() async {
        let store = store()
        #expect(await store.requestContacts() == .granted)
        #expect(await store.requestPhotos() == .granted)
        #expect(counter.requests == 2)
    }

    @Test func aWidgetThatIsNotPlacedIsNotRead() async {
        let store = store(library: .granted, contacts: .granted, folder: oneFolderPhoto)
        await store.refresh(allOn, for: [.activity], at: day(2026, 11, 5))
        #expect(counter.reads == 0)
    }

    @Test func readsOnceADay() async {
        let store = store(contacts: .granted)
        var settings = PersonalWidgetSettings()
        settings.isBirthdaysOn = true
        await store.refresh(settings, for: everything, at: day(2026, 11, 5, hour: 9))
        await store.refresh(settings, for: everything, at: day(2026, 11, 5, hour: 18))
        #expect(counter.reads == 1)
        await store.refresh(settings, for: everything, at: day(2026, 11, 6, hour: 9))
        #expect(counter.reads == 2)
    }

    @Test func birthdaysKeepOnlyWhatTheWidgetShows() async {
        let store = store(contacts: .granted)
        var settings = PersonalWidgetSettings()
        settings.isBirthdaysOn = true
        await store.refresh(settings, for: everything, at: day(2026, 11, 2))
        #expect(store.data.birthdays.state == .ready)
        #expect(store.data.birthdays.total == 1)
        #expect(store.data.birthdays.people.first?.name == "Anna Petrova")
    }

    @Test func folderPhotosGoToTheSharedContainer() async {
        let store = store(folder: oneFolderPhoto)
        await store.refresh(allOn, for: [.photoFrame], at: day(2026, 11, 5))
        #expect(store.data.photoFrame.state == .ready)
        #expect(store.data.photoFrame.folderName == "Travel 2025")
        #expect(store.data.photoFrame.total == 48)
        #expect(images.readData(for: "photoFrame-0") == Data([9]))
        #expect(images.readData(for: "photoFrame-0-thumb") == Data([8]))
    }

    @Test func aFolderThatCannotBeReadSaysSo() async {
        let store = store(folder: nil)
        await store.refresh(allOn, for: [.photoFrame], at: day(2026, 11, 5))
        #expect(store.data.photoFrame.state == .unreadable)
    }

    @Test func aNewFolderIsReadTheSameDay() async {
        let store = store(folder: oneFolderPhoto)
        var settings = allOn
        await store.refresh(settings, for: [.photoFrame], at: day(2026, 11, 5))
        settings.photoFolderPath = "/tmp/Other"
        await store.refresh(settings, for: [.photoFrame], at: day(2026, 11, 5))
        #expect(counter.reads == 2)
    }

    @Test func turningOffRemovesTheImages() async {
        let store = store(library: .granted, folder: oneFolderPhoto)
        await store.refresh(allOn, for: everything, at: day(2026, 11, 5))
        #expect(images.readData(for: "onThisDay-0") != nil)
        await store.refresh(PersonalWidgetSettings(), for: everything, at: day(2026, 11, 5))
        #expect(images.readData(for: "photoFrame-0") == nil)
        #expect(images.readData(for: "onThisDay-0-thumb") == nil)
        #expect(store.data == PersonalWidgetData())
    }

    @Test func accessTakenAwayLaterClearsThePhotos() async {
        var settings = PersonalWidgetSettings()
        settings.isOnThisDayOn = true
        let granted = store(library: .granted)
        await granted.refresh(settings, for: everything, at: day(2026, 11, 5))
        #expect(images.readData(for: "onThisDay-0") != nil)
        let denied = store(library: .denied)
        await denied.refresh(settings, for: everything, at: day(2026, 11, 5))
        #expect(denied.data.onThisDay.state == .noAccess)
    }
}

struct PersonalSettingsTests {
    @Test func aFileFromAnEarlierVersionLeavesThemOff() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.personalWidgets == PersonalWidgetSettings())
    }

    @Test func survivesARoundTrip() throws {
        var settings = AppSettings()
        settings.personalWidgets.isBirthdaysOn = true
        settings.personalWidgets.photoFolderPath = "/Users/me/Pictures"
        let copy = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(copy.personalWidgets == settings.personalWidgets)
    }

    @Test func aBadHandEditMeansOff() throws {
        let json = #"{"personalWidgets":{"isBirthdaysOn":"yes"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(!settings.personalWidgets.isBirthdaysOn)
    }
}

struct PhotoFolderReaderTests {
    private func write(_ name: String, to folder: URL) throws {
        let context = try #require(CGContext(
            data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let image = try #require(context.makeImage())
        let url = folder.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func readsImagesAndSkipsTheRest() async throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("one.jpg", to: folder)
        try write("two.JPG", to: folder)
        try Data("not a photo".utf8).write(to: folder.appending(path: "notes.txt"))
        let reading = try #require(await PhotoFolderReader().read(folder: folder, seed: 1, limit: 1))
        #expect(reading.total == 2)
        #expect(reading.photos.count == 1)
        let photo = try #require(reading.photos.first)
        #expect(!photo.image.isEmpty)
        #expect(photo.thumbnail.count < photo.image.count)
    }

    @Test func aMissingFolderIsNil() async {
        let missing = temporaryFolder().appending(path: "nope")
        #expect(await PhotoFolderReader().read(folder: missing, seed: 1, limit: 1) == nil)
    }
}
