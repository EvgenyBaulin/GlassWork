import Foundation
@testable import GlassWorkCore
import Testing

/// Settings for the system widgets: the refresh choice, when a Screen Time day starts, and Word of the Day.
struct WidgetOptionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// 2026-11-04 00:00 UTC.
    private let midnight = Date(timeIntervalSince1970: 1_793_750_400)

    @Test func anOldSettingsFileStillLoads() throws {
        let old = Data(#"{"refreshSeconds":300,"tracksScreenTime":true}"#.utf8)
        let settings = try JSONDecoder().decode(WidgetSettings.self, from: old)
        #expect(settings.refreshSeconds == 300)
        #expect(settings.tracksScreenTime)
        #expect(settings.dayStartHour == 0)
        #expect(settings.wordOfDay == WordOfDaySettings())
        #expect(settings.endpoints.isEmpty)
        #expect(try JSONDecoder().decode(WidgetSettings.self, from: Data("{}".utf8)) == WidgetSettings())
    }

    @Test func theNewChoicesSurviveASaveAndLoad() throws {
        var settings = WidgetSettings()
        settings.refreshSeconds = 900
        settings.dayStartHour = 4
        settings.wordOfDay.language = "ru"
        settings.wordOfDay.dictionaryID = "com.apple.dictionary.ru.oup"
        settings.wordOfDay.level = .any
        let back = try JSONDecoder().decode(WidgetSettings.self, from: JSONEncoder().encode(settings))
        #expect(back == settings)
    }

    @Test func theDayStartStaysInsideZeroToSix() throws {
        let high = try JSONDecoder().decode(WidgetSettings.self, from: Data(#"{"dayStartHour":19}"#.utf8))
        #expect(high.dayStartHour == 6)
        let low = try JSONDecoder().decode(WidgetSettings.self, from: Data(#"{"dayStartHour":-2}"#.utf8))
        #expect(low.dayStartHour == 0)
    }

    @Test func theRefreshChoicesAreMinutesUpToAnHour() {
        #expect(WidgetSettings.refreshChoices == [60, 300, 900, 1800, 3600])
    }

    @Test func timeBeforeTheDayStartCountsForTheDayBefore() {
        var log = ScreenTimeLog()
        log.dayStartHour = 4
        log.record(app: "Xcode", seconds: 60, at: midnight.addingTimeInterval(2 * 3600), calendar: calendar)
        log.record(app: "Xcode", seconds: 60, at: midnight.addingTimeInterval(5 * 3600), calendar: calendar)
        #expect(log.days.map(\.day) == ["2026-11-03", "2026-11-04"])
        #expect(log.dayStart(containing: midnight.addingTimeInterval(3 * 3600), calendar: calendar)
            == midnight.addingTimeInterval(-86400))
        #expect(log.dayStart(containing: midnight.addingTimeInterval(4 * 3600), calendar: calendar) == midnight)
    }

    @Test func aDayStartOfZeroKeepsCalendarDays() {
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: midnight.addingTimeInterval(2 * 3600), calendar: calendar)
        #expect(log.days.map(\.day) == ["2026-11-04"])
    }

    @Test func theWeekFollowsTheDayStart() {
        var log = ScreenTimeLog()
        log.dayStartHour = 4
        log.record(app: "Xcode", seconds: 600, at: midnight.addingTimeInterval(2 * 3600), calendar: calendar)
        let night = ScreenWeekStats(log: log, at: midnight.addingTimeInterval(3 * 3600), calendar: calendar)
        #expect(night.today == 600)
        let morning = ScreenWeekStats(log: log, at: midnight.addingTimeInterval(6 * 3600), calendar: calendar)
        #expect(morning.today == 0)
        #expect(morning.days[5].seconds == 600)
    }

    @Test func anOldLogLoadsWithTheDayStartAtMidnight() throws {
        let old = Data(#"{"days":[{"day":"2026-11-03","seconds":{"Xcode":5}}],"excluded":["Secret"]}"#.utf8)
        let log = try JSONDecoder().decode(ScreenTimeLog.self, from: old)
        #expect(log.dayStartHour == 0)
        #expect(log.excluded == ["Secret"])
        #expect(log.days.count == 1)
    }

    @MainActor
    @Test func resettingKeepsTheSettingsAndDropsTheData() {
        let activity = ActivityStore(store: SnapshotStore(directory: temporaryFolder()), locateGH: { nil })
        activity.configureScreenTime(dayStartHour: 3, excluded: ["Secret"])
        activity.appBecameActive("Xcode", at: midnight)
        activity.flushScreenTime(at: midnight.addingTimeInterval(60))
        #expect(!activity.screenTime.days.isEmpty)
        activity.resetScreenTime(at: midnight.addingTimeInterval(120))
        #expect(activity.screenTime.days.isEmpty)
        #expect(activity.screenTime.dayStartHour == 3)
        #expect(activity.screenTime.excluded == ["Secret"])
    }

    @MainActor
    @Test func anExcludedAppAddsNoTime() {
        let activity = ActivityStore(store: SnapshotStore(directory: temporaryFolder()), locateGH: { nil })
        activity.configureScreenTime(dayStartHour: 0, excluded: ["Secret"])
        activity.appBecameActive("Secret", at: midnight)
        activity.flushScreenTime(at: midnight.addingTimeInterval(60))
        #expect(activity.screenTime.days.isEmpty)
    }

    @Test func commonWordsComeFirstAndAnyAddsRarerOnes() {
        let common = WordList.words(language: "en", level: .common)
        let any = WordList.words(language: "en", level: .any)
        #expect(common == WordList.words)
        #expect(any.count > common.count)
        #expect(Array(any.prefix(common.count)) == common)
        #expect(Set(any).count == any.count)
        let russian = WordList.words(language: "ru", level: .any)
        #expect(russian.count > WordList.words(language: "ru", level: .common).count)
        #expect(Set(russian).count == russian.count)
        #expect(WordList.words(language: "xx", level: .common) == common)
    }

    @Test func theWordFollowsLanguageAndLevel() {
        let english = WordList.word(on: midnight, language: "en", level: .common, calendar: calendar)
        #expect(english == WordList.word(on: midnight, calendar: calendar))
        let russian = WordList.word(on: midnight, language: "ru", level: .common, calendar: calendar)
        #expect(WordList.russian.contains(russian))
    }

    @MainActor
    @Test func changingTheLanguageStartsTheWordsOver() {
        var asked: [String] = []
        let provider = WordOfDayProvider { word in
            asked.append(word)
            return "\(word) | x | noun a meaning: an example."
        }
        let before = provider.word(on: midnight, calendar: calendar)
        var settings = WordOfDaySettings()
        settings.language = "ru"
        provider.apply(settings, installed: [])
        let after = provider.word(on: midnight, calendar: calendar)
        #expect(WordList.words.contains(before.word))
        #expect(WordList.russian.contains(after.word))
        #expect(asked.count == 2)
        provider.apply(settings, installed: [])
        _ = provider.word(on: midnight, calendar: calendar)
        #expect(asked.count == 2)
    }

    @Test func aDictionaryOfAnotherLayoutGivesItsFirstMeaning() {
        let raw = "дом -а (-у), мн. дома, м. 1 Жилое здание, а также люди. Каменный дом. "
            + "ПРОИЗВОДНЫЕ уменьш. домик"
        let entry = DictionaryEntryParser.parsePlain(raw, word: "дом")
        #expect(entry.definition?.hasPrefix("-а (-у)") == true)
        #expect(entry.definition?.contains("ПРОИЗВОДНЫЕ") == false)
        #expect(DictionaryEntryParser.parsePlain("", word: "дом") == DictionaryEntry())
    }

    @Test func installedDictionariesAreReadFromTheirInfoFiles() throws {
        let folder = temporaryFolder()
        let bundle = folder.appending(path: "Asset/AssetData/Russian.dictionary/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.ru",
            "CFBundleName": "Russian",
            "DCSDictionaryLanguages": [
                ["DCSDictionaryIndexLanguage": "ru", "DCSDictionaryDescriptionLanguage": "ru"],
                ["DCSDictionaryIndexLanguage": "en", "DCSDictionaryDescriptionLanguage": "ru"],
            ],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Info.plist"))
        defer { try? FileManager.default.removeItem(at: folder) }

        let found = SystemDictionaries.installed(in: [folder])
        #expect(found.map(\.id) == ["com.example.ru"])
        #expect(found.first?.languages == ["ru", "en"])
        #expect(SystemDictionaries.languages(in: found) == ["en", "ru"])
        #expect(SystemDictionaries.languages(in: []) == ["en"])
        #expect(SystemDictionaries.dictionaries(for: "ru", in: found).count == 1)
        #expect(SystemDictionaries.installed(in: [folder.appending(path: "missing")]).isEmpty)
    }
}
