import Foundation
@testable import GlassWorkCore
import Testing

struct GlobalShortcutKeyTests {
    @Test func theKeysKeepTheirSystemNumbers() {
        #expect(GlobalShortcut.Key.space.code == 49)
        #expect(GlobalShortcut.Key.letterQ.code == 12)
        #expect(GlobalShortcut.Key.letterV.code == 9)
        #expect(GlobalShortcut.Key.digit2.code == 19)
        #expect(GlobalShortcut.Key.leftArrow.code == 123)
        #expect(GlobalShortcut.Key.returnKey.code == 36)
    }

    @Test(arguments: [(0, "A"), (45, "N"), (18, "1"), (122, "F1"), (111, "F12"), (48, "⇥"), (999, "#999")])
    func keysHaveLabels(code: Int, label: String) {
        #expect(GlobalShortcut.Key(code: code).label == label)
    }

    @Test func shortcutsRoundTripThroughJSON() throws {
        let shortcut = GlobalShortcut([.control, .shift], GlobalShortcut.Key(code: 45))
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(GlobalShortcut.self, from: data) == shortcut)
    }

    @Test func shiftAloneIsNotEnough() {
        #expect(!GlobalShortcut([.shift], .letterQ).hasRequiredModifier)
        #expect(!GlobalShortcut([], .letterQ).hasRequiredModifier)
        #expect(GlobalShortcut([.option], .letterQ).hasRequiredModifier)
    }

    @Test func anFKeyCanStandAlone() {
        #expect(GlobalShortcut([], GlobalShortcut.Key(code: 122)).hasRequiredModifier)
    }
}

struct ShortcutActionTests {
    @Test func idsAreUnique() {
        let ids = ShortcutAction.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyActionHasItsOwnDefault() {
        let shortcuts = ShortcutAction.all.map(\.defaultShortcut)
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    @Test func theDefaultsAreTheOnesPeopleKnow() {
        #expect(ShortcutAction.hub.defaultShortcut.label == "⌃⌥Space")
        #expect(ShortcutAction.quickPaste.defaultShortcut.label == "⇧⌘V")
        #expect(ShortcutAction.textCapture.defaultShortcut.label == "⇧⌘2")
        #expect(ShortcutAction.quickQuit.defaultShortcut.label == "⌃⌥Q")
    }

    @Test func idsAreStable() {
        #expect(ShortcutAction.tile(.place(.leftHalf)).id == "tile.leftHalf")
        #expect(ShortcutAction.tile(.nextDisplay).id == "tile.nextDisplay")
    }

    @Test func everyDefaultIsAcceptedByItsOwnCheck() {
        for action in ShortcutAction.all {
            #expect(ShortcutCheck(action.defaultShortcut, for: action, in: ShortcutSettings()) == .ok, "\(action)")
        }
    }
}

struct ShortcutSettingsTests {
    private let custom = GlobalShortcut([.control, .option], GlobalShortcut.Key(code: 45))

    @Test func nothingChangedMeansTheDefaults() {
        let settings = ShortcutSettings()
        for action in ShortcutAction.all {
            #expect(settings.shortcut(for: action) == action.defaultShortcut)
        }
    }

    @Test func aChangeIsKept() {
        var settings = ShortcutSettings()
        settings.set(.hub, to: custom)
        #expect(settings.shortcut(for: .hub) == custom)
        #expect(settings.shortcut(for: .quickQuit) == ShortcutAction.quickQuit.defaultShortcut)
    }

    @Test func aClearedShortcutIsNotTheDefault() {
        var settings = ShortcutSettings()
        settings.set(.hub, to: nil)
        #expect(settings.shortcut(for: .hub) == nil)
    }

    @Test func settingTheDefaultStoresNothing() {
        var settings = ShortcutSettings()
        settings.set(.hub, to: custom)
        settings.set(.hub, to: ShortcutAction.hub.defaultShortcut)
        #expect(settings.bindings.isEmpty)
    }

    @Test func replacingTakesTheShortcutAwayFromItsHolder() {
        var settings = ShortcutSettings()
        settings.replace(.hub, with: ShortcutAction.quickQuit.defaultShortcut)
        #expect(settings.shortcut(for: .hub) == ShortcutAction.quickQuit.defaultShortcut)
        #expect(settings.shortcut(for: .quickQuit) == nil)
    }

    @Test func restoringForgetsEveryChange() {
        var settings = ShortcutSettings()
        settings.set(.hub, to: custom)
        settings.set(.quickQuit, to: nil)
        settings.restoreDefaults()
        #expect(settings == ShortcutSettings())
    }

    @Test func aBrokenEntryCostsOnlyItself() throws {
        let json = #"{"bindings": [{"action": "hub", "shortcut": {"key": "oops"}},"#
            + #" {"action": "quickQuit"}]}"#
        let settings = try JSONDecoder().decode(ShortcutSettings.self, from: Data(json.utf8))
        #expect(settings.shortcut(for: .hub) == ShortcutAction.hub.defaultShortcut)
        #expect(settings.shortcut(for: .quickQuit) == nil)
    }

    @Test func aBrokenSectionCostsOnlyItself() throws {
        let json = #"{"shortcuts": 5, "numberStyle": "precise"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.shortcuts == ShortcutSettings())
        #expect(settings.numberStyle == .precise)
    }

    /// Saving merges dictionaries with what the file already holds, which would bring the old shortcut back.
    @Test func aRestoredShortcutStaysRestoredAfterTheFile() throws {
        let file = SettingsFile(url: temporaryFolder().appending(path: "settings.json"))
        var settings = AppSettings()
        settings.shortcuts.set(.hub, to: custom)
        try file.save(settings)

        settings.shortcuts.restoreDefaults()
        try file.save(settings)

        #expect(try file.load()?.shortcuts.shortcut(for: .hub) == ShortcutAction.hub.defaultShortcut)
    }

    @Test func changesSurviveTheFile() throws {
        let file = SettingsFile(url: temporaryFolder().appending(path: "settings.json"))
        var settings = AppSettings()
        settings.shortcuts.set(.hub, to: custom)
        settings.shortcuts.set(.quickQuit, to: nil)
        try file.save(settings)

        let loaded = try file.load()?.shortcuts
        #expect(loaded?.shortcut(for: .hub) == custom)
        #expect(loaded?.shortcut(for: .quickQuit) == nil)
        #expect(loaded == settings.shortcuts)
    }
}

struct ShortcutCheckTests {
    private let settings = ShortcutSettings()

    @Test func aFreeShortcutPasses() {
        let free = GlobalShortcut([.control, .option], GlobalShortcut.Key(code: 45))
        #expect(ShortcutCheck(free, for: .hub, in: settings) == .ok)
    }

    @Test func aPlainLetterIsNotEnough() {
        #expect(ShortcutCheck(GlobalShortcut([], .letterQ), for: .hub, in: settings) == .needsModifier)
    }

    @Test func anotherActionsShortcutIsTaken() {
        let check = ShortcutCheck(ShortcutAction.quickQuit.defaultShortcut, for: .hub, in: settings)
        #expect(check == .taken(.quickQuit))
    }

    @Test func aTileShortcutCountsEvenWhenTilesAreOff() {
        let check = ShortcutCheck(TileCommand.place(.center).defaultShortcut, for: .hub, in: settings)
        #expect(check == .taken(.tile(.place(.center))))
    }

    @Test func anActionDoesNotClashWithItself() {
        #expect(ShortcutCheck(ShortcutAction.hub.defaultShortcut, for: .hub, in: settings) == .ok)
    }

    @Test func aClearedShortcutIsFreeAgain() {
        var settings = ShortcutSettings()
        settings.set(.quickQuit, to: nil)
        #expect(ShortcutCheck(ShortcutAction.quickQuit.defaultShortcut, for: .hub, in: settings) == .ok)
    }

    @Test func spotlightIsCaught() {
        let check = ShortcutCheck(GlobalShortcut([.command], .space), for: .hub, in: settings)
        #expect(check == .system(name: "Spotlight"))
    }

    @Test func ownClashesComeBeforeSystemOnes() {
        var settings = ShortcutSettings()
        settings.set(.quickQuit, to: GlobalShortcut([.command], .space))
        let check = ShortcutCheck(GlobalShortcut([.command], .space), for: .hub, in: settings)
        #expect(check == .taken(.quickQuit))
    }

    @Test func noDefaultUsesASystemShortcut() {
        let system = Set(SystemShortcut.known.map(\.shortcut))
        #expect(system.isDisjoint(with: ShortcutAction.all.map(\.defaultShortcut)))
    }
}

struct ShortcutRecordingTests {
    @Test func bareEscapeCancels() {
        #expect(ShortcutRecording(key: .escape, modifiers: []) == .cancel)
    }

    @Test func bareDeleteClears() {
        #expect(ShortcutRecording(key: .delete, modifiers: []) == .clear)
    }

    @Test func anythingElseIsRecorded() {
        let shortcut = GlobalShortcut([.control], .letterQ)
        #expect(ShortcutRecording(key: .letterQ, modifiers: [.control]) == .record(shortcut))
    }

    @Test func withModifiersThoseKeysAreOrdinary() {
        let shortcut = GlobalShortcut([.command], .delete)
        #expect(ShortcutRecording(key: .delete, modifiers: [.command]) == .record(shortcut))
    }
}
