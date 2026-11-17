import Foundation
@testable import GlassWorkCore
import Testing

@MainActor
struct SettingsRedoTests {
    private func store() -> SettingsStore {
        SettingsStore(file: SettingsFile(url: FileManager.default.temporaryDirectory
                .appending(path: "GlassWorkRedo-\(UUID().uuidString)/settings.json")))
    }

    @Test func redoBringsBackWhatUndoTookAway() {
        let store = store()
        store.update { $0.numberStyle = .precise }
        store.undo()
        let change = store.redo()

        #expect(store.settings.numberStyle == .precise)
        #expect(change == SettingsChange(area: .numberStyle))
        #expect(store.redoStack.isEmpty)
        #expect(store.undoStack.count == 1)
    }

    @Test func aNewChangeClearsTheRedoStack() {
        let store = store()
        store.update { $0.numberStyle = .precise }
        store.undo()
        store.update { $0.keepsDiagnosticLog = true }

        #expect(store.redoStack.isEmpty)
        #expect(store.redo() == nil)
        #expect(store.settings.numberStyle == .compact)
    }

    @Test func replacingClearsTheRedoStack() {
        let store = store()
        store.update { $0.numberStyle = .precise }
        store.undo()
        store.replace(with: AppSettings())

        #expect(store.redoStack.isEmpty)
    }

    @Test func undoAndRedoDoNothingOnEmptyStacks() {
        let store = store()
        #expect(store.undo() == nil)
        #expect(store.redo() == nil)
    }

    @Test func resettingWithoutABackupWritesNone() {
        let store = store()
        store.update { $0.numberStyle = .precise }
        store.replace(with: AppSettings(), backup: false)

        #expect(store.backups.list().isEmpty)
        #expect(store.settings.numberStyle == .compact)
    }

    @Test func resettingWithABackupKeepsTheOldSettings() throws {
        let store = store()
        store.update { $0.numberStyle = .precise }
        store.replace(with: AppSettings(), backup: true)

        let backup = try #require(store.backups.list().first)
        #expect(store.backups.load(backup)?.numberStyle == .precise)
    }

    @Test func aBackupIsNamedAfterItsDate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "GlassWorkNames-\(UUID().uuidString)")
        let url = try #require(SettingsBackups(directory: directory)
            .create(from: AppSettings(), at: Date(timeIntervalSince1970: 1_800_000_000)))

        #expect(url.lastPathComponent.hasPrefix("settings-2027-"))
        #expect(url.pathExtension == "json")
        #expect(!url.lastPathComponent.contains(":"))
    }

    @Test func aSingleModuleChangeNamesTheModule() {
        var changed = AppSettings()
        changed.update(.weather) { $0.mode = .off }

        #expect(SettingsChange(from: AppSettings(), to: changed) == SettingsChange(area: .modules, module: .weather))
    }

    @Test func severalAreasAreJustSettings() {
        var changed = AppSettings()
        changed.numberStyle = .precise
        changed.keepsDiagnosticLog = true

        #expect(SettingsChange(from: AppSettings(), to: changed).area == .other)
    }
}

struct UpdatePauseTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: hour, minute: minute))!
    }

    @Test func fixedPausesEndAfterTheirDuration() {
        let now = date(14, 0)
        #expect(UpdatePause.fifteenMinutes.end(from: now, calendar: calendar) == date(14, 15))
        #expect(UpdatePause.oneHour.end(from: now, calendar: calendar) == date(15, 0))
    }

    @Test func untilTomorrowEndsAtTheNextMidnight() {
        let end = UpdatePause.untilTomorrow.end(from: date(23, 50), calendar: calendar)
        #expect(end == calendar.date(from: DateComponents(year: 2026, month: 11, day: 18)))
    }

    @Test func anIndefinitePauseHasNoEnd() {
        #expect(UpdatePause.indefinitely.end(from: date(9), calendar: calendar) == nil)
    }
}
