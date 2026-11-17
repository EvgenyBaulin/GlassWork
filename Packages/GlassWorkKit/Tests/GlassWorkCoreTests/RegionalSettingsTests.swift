import Foundation
@testable import GlassWorkCore
import Testing

struct RegionalSettingsTests {
    private let english = Locale(identifier: "en_US")
    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = 1
        return calendar
    }

    /// 14:00 UTC on 17 November 2026.
    private let afternoon = Date(timeIntervalSince1970: 1_794_924_000)

    private func time(_ settings: RegionalSettings) -> String {
        var style = Date.FormatStyle().hour().minute()
        style.timeZone = .gmt
        style.locale = settings.locale(base: english)
        return afternoon.formatted(style)
    }

    @Test func systemChangesNothing() {
        let settings = RegionalSettings()
        #expect(settings.locale(base: english) == english)
        #expect(settings.calendar(base: gregorian) == gregorian)
        #expect(settings.locale() == Locale.current)
        #expect(settings.calendar() == Calendar.current)
    }

    @Test func timeFormatIsOverridden() {
        var settings = RegionalSettings()
        settings.timeFormat = .twentyFourHour
        #expect(time(settings) == "14:00")
        settings.timeFormat = .twelveHour
        #expect(time(settings).hasPrefix("2:00"))
    }

    @Test func firstWeekdayIsOverridden() {
        var settings = RegionalSettings()
        settings.firstWeekday = .monday
        #expect(settings.calendar(base: gregorian).firstWeekday == 2)
        settings.firstWeekday = .sunday
        var monday = gregorian
        monday.firstWeekday = 2
        #expect(settings.calendar(base: monday).firstWeekday == 1)
    }

    @Test func monthGridFollowsTheFirstWeekday() throws {
        // 1 November 2026 is a Sunday.
        let november = try #require(gregorian.date(from: DateComponents(year: 2026, month: 11, day: 15)))
        var settings = RegionalSettings()
        settings.firstWeekday = .sunday
        let sundayFirst = MonthRows.rows(for: november, calendar: settings.calendar(base: gregorian))
        #expect(sundayFirst[0].days.first == 1)
        settings.firstWeekday = .monday
        let mondayFirst = MonthRows.rows(for: november, calendar: settings.calendar(base: gregorian))
        #expect(mondayFirst[0].days.prefix(6).allSatisfy { $0 == nil })
        #expect(mondayFirst[0].days[6] == 1)
    }

    @Test func settingsRoundTripAndDefaultsWhenMissing() throws {
        var settings = AppSettings()
        #expect(settings.regional == RegionalSettings())
        settings.regional.language = .russian
        settings.regional.timeFormat = .twentyFourHour
        settings.regional.firstWeekday = .monday
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.regional == settings.regional)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.regional == RegionalSettings())
    }

    @Test func anUnknownValueFallsBackToSystem() throws {
        let json = Data(#"{"language":"klingon","timeFormat":"twelveHour"}"#.utf8)
        let decoded = try JSONDecoder().decode(RegionalSettings.self, from: json)
        #expect(decoded.language == .system)
        #expect(decoded.timeFormat == .twelveHour)
    }

    @Test func languageOverrideReadsOnlyTheAppDomain() throws {
        let name = "GlassWorkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(LanguageOverride.stored(defaults: defaults, domain: name) == .system)
        LanguageOverride.apply(.russian, defaults: defaults, domain: name)
        #expect(LanguageOverride.stored(defaults: defaults, domain: name) == .russian)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["ru"])
        LanguageOverride.apply(.english, defaults: defaults, domain: name)
        #expect(LanguageOverride.stored(defaults: defaults, domain: name) == .english)
        LanguageOverride.apply(.system, defaults: defaults, domain: name)
        #expect(LanguageOverride.stored(defaults: defaults, domain: name) == .system)
    }

    @Test func dateItemsStartFromTheSharedSettings() {
        #expect(DateItemText().locale == RegionalFormat.locale)
    }
}
