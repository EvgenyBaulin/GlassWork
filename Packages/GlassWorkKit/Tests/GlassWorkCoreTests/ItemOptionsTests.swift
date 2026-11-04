import Foundation
@testable import GlassWorkCore
import Testing

struct OptionReadingTests {
    @Test func aMissingEntryMeansTheDefault() {
        let options: [String: String] = [:]
        #expect(options.flag("key", default: true))
        #expect(options.number("key", default: 7) == 7)
        #expect(options.choice("key", default: MemoryFigure.pressure) == .pressure)
    }

    @Test func anUnreadableEntryMeansTheDefault() {
        let options = ["number": "many", "choice": "sideways"]
        #expect(options.number("number", default: 7) == 7)
        #expect(options.choice("choice", default: MemoryFigure.share) == .share)
    }

    @Test func storedValuesWin() {
        let options = ["flag": "false", "number": "3", "choice": "gigabytes"]
        #expect(!options.flag("flag", default: true))
        #expect(options.number("number", default: 7) == 3)
        #expect(options.choice("choice", default: MemoryFigure.share) == .gigabytes)
    }
}

struct ColourFormatTests {
    @Test(arguments: [
        (true, true, "#6B5BB5"),
        (false, true, "#6b5bb5"),
        (true, false, "6B5BB5"),
        (false, false, "6b5bb5"),
    ])
    func hexFollowsCaseAndHash(isUppercase: Bool, hasHash: Bool, expected: String) {
        #expect(ColourFormat.hex.text(hex: "#6B5BB5", isUppercase: isUppercase, hasHash: hasHash) == expected)
    }

    @Test func rgbGivesTheChannels() {
        #expect(ColourFormat.rgb.text(hex: "#6B5BB5", isUppercase: true, hasHash: true) == "rgb(107, 91, 181)")
    }

    @Test(arguments: [
        ("#6B5BB5", "hsl(251, 38%, 53%)"),
        ("#FF0000", "hsl(0, 100%, 50%)"),
        ("#00FF00", "hsl(120, 100%, 50%)"),
        ("#0000FF", "hsl(240, 100%, 50%)"),
        ("#FF00FF", "hsl(300, 100%, 50%)"),
        ("#000000", "hsl(0, 0%, 0%)"),
        ("#FFFFFF", "hsl(0, 0%, 100%)"),
    ])
    func hslMatchesKnownColours(hex: String, expected: String) {
        #expect(ColourFormat.hsl.text(hex: hex, isUppercase: true, hasHash: true) == expected)
    }

    @Test func somethingElseComesBackUnchanged() {
        #expect(ColourFormat.rgb.text(hex: "red", isUppercase: true, hasHash: true) == "red")
    }

    @Test func theListKeepsAsManyAsAsked() {
        var data = EverydayData()
        for index in 0 ..< 6 {
            data.addColor("#00000\(index)", limit: 4)
        }
        #expect(data.colors.count == 4)
        #expect(data.colors.first == "#000005")
    }
}

struct BitRateFormatTests {
    @Test func compactBits() {
        #expect(Format.bitRate(1_000_000) == "8Mb/s")
        #expect(Format.bitRate(125_000) == "1Mb/s")
        #expect(Format.bitRate(100) == "800b/s")
    }

    @Test func preciseBits() {
        #expect(Format.bitRate(1_000_000, style: .precise) == "8.0 Mbit/s")
        #expect(Format.bitRate(0, style: .precise) == "0.0 bit/s")
    }
}

struct UptimeFormatTests {
    private let interval: TimeInterval = 76 * 3600 + 12 * 60 + 30

    @Test func hoursAndMinutes() {
        #expect(UptimeFormat.hoursText(interval) == "76:12")
        #expect(UptimeFormat.hoursText(59) == "0:00")
    }

    @Test func wholeDays() {
        #expect(UptimeFormat.wholeDays(interval) == 3)
        #expect(UptimeFormat.wholeDays(-5) == 0)
    }
}

struct TimerPresetTests {
    @Test func readsMinutesInTheOrderTyped() {
        #expect(TimerPresets.parse("25, 5,10") == [25, 5, 10])
    }

    @Test func dropsRepeatsAndWhatCannotBeATimer() {
        #expect(TimerPresets.parse("5 5 0 99999 tea 7") == [5, 7])
    }

    @Test func nothingUsableMeansTheStandardList() {
        #expect(TimerPresets.parse(nil) == TimerPresets.standard)
        #expect(TimerPresets.parse("") == TimerPresets.standard)
        #expect(TimerPresets.parse("soon") == TimerPresets.standard)
    }
}

struct DateItemTextTests {
    /// Monday 2 November 2026, 12:00 UTC.
    private let date = Date(timeIntervalSince1970: 1_793_620_800)

    private func text(_ change: (inout DateItemText) -> Void = { _ in }) -> DateItemText {
        var text = DateItemText()
        text.locale = Locale(identifier: "en_US_POSIX")
        text.timeZone = TimeZone(identifier: "UTC") ?? .current
        change(&text)
        return text
    }

    @Test func weekdayDayMonthByDefault() {
        let result = text().text(for: date)
        #expect(result.contains("Mon"))
        #expect(result.contains("Nov"))
        #expect(!result.contains("W"))
    }

    @Test func addsTheWeekNumber() {
        #expect(text { $0.showsWeek = true }.text(for: date).hasSuffix(" · W45"))
    }

    @Test func aCustomPatternIsUsedAsTyped() {
        let result = text {
            $0.figure = .custom
            $0.pattern = "yyyy/MM/dd"
        }
        #expect(result.text(for: date) == "2026/11/02")
    }

    @Test func anEmptyPatternStillShowsTheDate() {
        #expect(text { $0.figure = .custom }.text(for: date).contains("Nov"))
    }

    @Test func readsItsOptions() {
        let result = DateItemText(options: [
            ItemOption.dateFigure: "custom",
            ItemOption.datePattern: "d",
            ItemOption.showsWeek: "true",
            ItemOption.weekNumbering: "system",
        ])
        #expect(result.figure == .custom)
        #expect(result.pattern == "d")
        #expect(result.showsWeek)
        #expect(result.numbering == .system)
    }
}

struct CalendarItemTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(in hours: Double, isAllDay: Bool = false) -> AgendaEvent {
        let start = now.addingTimeInterval(hours * 3600)
        return AgendaEvent(
            id: "\(hours)",
            title: "Yoga",
            start: start,
            end: start.addingTimeInterval(1800),
            isAllDay: isAllDay
        )
    }

    @Test func anEventInsideTheWindowIsShown() {
        #expect(CalendarItem.next(in: [event(in: 2)], at: now, windowHours: 4, skipsAllDay: true) != nil)
    }

    @Test func anEventPastTheWindowIsNot() {
        #expect(CalendarItem.next(in: [event(in: 6)], at: now, windowHours: 4, skipsAllDay: true) == nil)
    }

    @Test func aWindowOfZeroMeansAnyTime() {
        #expect(CalendarItem.next(in: [event(in: 40)], at: now, windowHours: 0, skipsAllDay: true) != nil)
    }

    @Test func allDayEventsCountOnlyWhenAsked() {
        let events = [event(in: 1, isAllDay: true)]
        #expect(CalendarItem.next(in: events, at: now, windowHours: 4, skipsAllDay: true) == nil)
        #expect(CalendarItem.next(in: events, at: now, windowHours: 4, skipsAllDay: false) != nil)
    }

    @Test func titlesAreCutToTheLimit() {
        #expect(CalendarItem.title("Quarterly review", limit: 8) == "Quarter…")
        #expect(CalendarItem.title("Yoga", limit: 8) == "Yoga")
    }

    @Test func theWarningFollowsTheChosenTime() {
        #expect(EndsInUrgency(remaining: 500, warnAt: 600) == .soon)
        #expect(EndsInUrgency(remaining: 500) == .normal)
        #expect(EndsInUrgency(remaining: 30, warnAt: 600) == .lastMinute)
    }
}

@MainActor
struct HubSettingsTests {
    private func file() -> SettingsFile {
        SettingsFile(url: temporaryFolder().appending(path: "settings.json"))
    }

    @Test func survivesTheFile() throws {
        let file = file()
        var settings = AppSettings()
        settings.hub.isGrouped = false
        settings.hub.tileSize = .large
        settings.hub.showsMenuBarModules = false

        try file.save(settings)

        #expect(try file.load()?.hub == settings.hub)
    }

    @Test func aBrokenSectionCostsOnlyItself() throws {
        let json = #"{"hub": {"tileSize": "enormous"}, "numberStyle": "precise"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.hub == HubSettings())
        #expect(settings.numberStyle == .precise)
    }

    @Test func missingKeysKeepTheirDefaults() throws {
        let settings = try JSONDecoder().decode(HubSettings.self, from: Data(#"{"isGrouped": false}"#.utf8))
        #expect(!settings.isGrouped)
        #expect(settings.tileSize == .medium)
        #expect(settings.showsMenuBarModules)
    }
}

struct GitDiscoveryOptionTests {
    private func folderWithRepositories() throws -> String {
        let root = temporaryFolder()
        for path in ["top/.git", "group/nested/.git"] {
            try FileManager.default.createDirectory(
                at: root.appending(path: path),
                withIntermediateDirectories: true
            )
        }
        return GitDiscovery.plainPath(root)
    }

    @Test func twoLevelsFindNestedRepositories() throws {
        let root = try folderWithRepositories()
        let found = GitDiscovery.repositories(in: root, depth: 2).map { URL(filePath: $0).lastPathComponent }
        #expect(found.sorted() == ["nested", "top"])
    }

    @Test func oneLevelStopsAtTheTop() throws {
        let root = try folderWithRepositories()
        let found = GitDiscovery.repositories(in: root, depth: 1).map { URL(filePath: $0).lastPathComponent }
        #expect(found == ["top"])
    }

    @Test func optionsReadFromSettings() {
        var settings = AppSettings()
        settings.update(.git) { module in
            module.options[DeveloperOptions.Key.autoDiscover] = "false"
            module.options[DeveloperOptions.Key.searchDepth] = "1"
        }
        let options = DeveloperOptions(settings: settings)
        #expect(!options.gitAutoDiscover)
        #expect(options.gitSearchDepth == 1)
        #expect(DeveloperOptions().gitAutoDiscover)
        #expect(DeveloperOptions().gitSearchDepth == 2)
    }
}
