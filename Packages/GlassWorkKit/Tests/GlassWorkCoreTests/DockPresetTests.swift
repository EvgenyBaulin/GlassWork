import Foundation
@testable import GlassWorkCore
import Testing

struct DockPresetTests {
    private let mail = DockApp(path: "/Applications/Mail.app", name: "Mail")
    private let stack = DockStack(path: "/tmp/docs", name: "Docs")

    private func builtIn(_ id: DockPresetID, exists: (String) -> Bool = { _ in true }) -> DockPreset {
        DockPresets.builtIn(id, exists: exists)
    }

    private func dock(_ items: [DockItem] = []) -> DockSettings {
        var dock = DockSettings()
        dock.items = items
        return dock
    }

    @Test func thereAreFiveAndEachOffersOnlyRealWidgets() {
        #expect(DockPresetID.allCases.count == 5)
        for id in DockPresetID.allCases {
            let preset = builtIn(id)
            #expect(!preset.widgets.isEmpty)
            #expect(Set(preset.widgets).isSubset(of: ModuleID.dockWidgets))
            #expect(Set(preset.widgets).count == preset.widgets.count)
        }
    }

    @Test func aFolderHoldsOnlyWhatIsInstalled() throws {
        let preset = builtIn(.everyday) { $0.hasSuffix("Calculator.app") || $0.hasSuffix("Clock.app") }
        let folder = try #require(preset.folders.first)
        #expect(folder.apps.map(\.name) == ["Calculator", "Clock"])
    }

    @Test func aFolderOfOneOrNoneIsLeftOut() {
        #expect(builtIn(.everyday) { $0.hasSuffix("Calculator.app") }.folders.isEmpty)
        #expect(builtIn(.everyday) { _ in false }.folders.isEmpty)
    }

    @Test func folderNamesAreTranslated() {
        let preset = DockPresets.builtIn(.productivity, exists: { _ in true }, title: { "ru-\($0)" })
        #expect(preset.folders.first?.name == "ru-Office")
    }

    @Test func applyingKeepsAppsAndStacks() {
        var settings = dock([.app(mail), .stack(stack), .widget(.cpu)])
        DockPresets.apply(builtIn(.student), current: nil, to: &settings)
        #expect(settings.items.contains(.app(mail)))
        #expect(settings.stacks == [stack])
        #expect(settings.widgets == [.calendar, .timers, .countdown])
        #expect(settings.activePreset == DockPresetID.student.rawValue)
    }

    /// Reading a folder can raise a macOS prompt, so no preset may bring a stack.
    @Test func noPresetAddsAStack() {
        for id in DockPresetID.allCases {
            var settings = dock()
            DockPresets.apply(builtIn(id), current: nil, to: &settings)
            #expect(settings.stacks.isEmpty)
            #expect(settings.foldersToRead.isEmpty)
        }
    }

    @Test func theOwnersFoldersStay() {
        let own = AppFolder(name: "Mine", apps: [mail])
        var settings = dock([.folder(own)])
        DockPresets.apply(builtIn(.student), current: nil, to: &settings)
        #expect(settings.folders.contains(own))
    }

    @Test func aPresetsFoldersGoWhenAnotherComes() {
        var settings = dock()
        DockPresets.apply(builtIn(.productivity), current: nil, to: &settings)
        #expect(settings.folders.map(\.name) == ["Office"])
        DockPresets.apply(builtIn(.student), current: builtIn(.productivity), to: &settings)
        #expect(settings.folders.map(\.name) == ["Study"])
    }

    @Test func anOwnFolderOfTheSameNameIsNotDoubled() {
        let own = AppFolder(name: "Office", apps: [mail])
        var settings = dock([.folder(own)])
        DockPresets.apply(builtIn(.productivity), current: nil, to: &settings)
        #expect(settings.folders.map(\.name) == ["Office"])
    }

    @Test func everyApplyMakesFreshFolders() {
        let preset = builtIn(.productivity)
        var first = dock()
        var second = dock()
        DockPresets.apply(preset, current: nil, to: &first)
        DockPresets.apply(preset, current: nil, to: &second)
        #expect(first.folders.first?.id != second.folders.first?.id)
        #expect(first.folders.first?.id != preset.folders.first?.id)
    }

    @Test func applyingTheSamePresetTwiceChangesNothing() {
        let preset = builtIn(.everyday)
        var settings = dock([.app(mail)])
        DockPresets.apply(preset, current: nil, to: &settings)
        let once = settings.items.count
        DockPresets.apply(preset, current: preset, to: &settings)
        #expect(settings.items.count == once)
        #expect(settings.presets.isEmpty)
    }

    @Test func changesToThePresetInUseAreKeptWithIt() throws {
        let everyday = builtIn(.everyday)
        var settings = dock()
        DockPresets.apply(everyday, current: nil, to: &settings)
        settings.items = DockLayout.setting(widgets: [.battery], in: settings.items)
        DockPresets.apply(builtIn(.student), current: everyday, to: &settings)

        let all = DockPresets.all(in: settings, exists: { _ in true })
        let kept = try #require(all.first { $0.id == everyday.id })
        #expect(kept.widgets == [.battery])
        #expect(DockPresets.isEdited(kept, in: settings))
    }

    @Test func leavingAnUnchangedPresetStoresNothing() {
        let everyday = builtIn(.everyday)
        var settings = dock()
        DockPresets.apply(everyday, current: nil, to: &settings)
        DockPresets.apply(builtIn(.student), current: everyday, to: &settings)
        #expect(settings.presets.isEmpty)
    }

    /// Having a folder of your own is not a change to the preset.
    @Test func anOwnFolderDoesNotMarkThePresetEdited() {
        let everyday = builtIn(.everyday)
        var settings = dock([.folder(AppFolder(name: "Mine", apps: [mail]))])
        DockPresets.apply(everyday, current: nil, to: &settings)
        DockPresets.apply(builtIn(.student), current: everyday, to: &settings)
        #expect(settings.presets.isEmpty)
    }

    @Test func anEditedBuiltInGoesBackToTheOriginal() throws {
        var settings = dock()
        DockPresets.store(DockPreset(id: "everyday", name: "everyday", widgets: [.cpu]), in: &settings)
        let edited = try #require(DockPresets.all(in: settings, exists: { _ in true }).first)
        #expect(edited.widgets == [.cpu])
        DockPresets.remove(edited, from: &settings)
        #expect(try #require(DockPresets.all(in: settings, exists: { _ in true }).first).widgets != [.cpu])
    }

    @Test func theOwnersPresetsComeAfterTheBuiltIns() {
        var settings = dock()
        DockPresets.store(DockPreset(id: UUID().uuidString, name: "Mine", widgets: [.cpu]), in: &settings)
        let all = DockPresets.all(in: settings, exists: { _ in true })
        #expect(all.count == 6)
        #expect(all.last?.name == "Mine")
        #expect(all.last?.isBuiltIn == false)
    }

    @Test func deletingThePresetInUseClearsIt() {
        let own = DockPreset(id: UUID().uuidString, name: "Mine", widgets: [])
        var settings = dock()
        DockPresets.store(own, in: &settings)
        settings.activePreset = own.id
        DockPresets.remove(own, from: &settings)
        #expect(settings.presets.isEmpty)
        #expect(settings.activePreset == nil)
    }

    @Test func storingAgainReplaces() {
        var settings = dock()
        DockPresets.store(DockPreset(id: "a", name: "One", widgets: []), in: &settings)
        DockPresets.store(DockPreset(id: "a", name: "Two", widgets: []), in: &settings)
        #expect(settings.presets.map(\.name) == ["Two"])
    }

    @Test func capturingTakesWidgetsAndFolders() {
        let folder = AppFolder(name: "Work", apps: [mail])
        let preset = DockPresets.capture(dock([.widget(.cpu), .folder(folder), .stack(stack)]), id: "x", name: "X")
        #expect(preset.widgets == [.cpu])
        #expect(preset.folders == [folder])
    }

    @Test func survivesARoundTripWithItsPresets() throws {
        var settings = dock()
        DockPresets.apply(builtIn(.developer), current: nil, to: &settings)
        DockPresets.store(DockPreset(id: "x", name: "X", widgets: [.cpu]), in: &settings)
        let copy = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(copy == settings)
    }

    @Test func aWidgetItCannotReadDoesNotCostThePreset() throws {
        let preset = try JSONDecoder().decode(DockPreset.self, from: Data("""
        {"id": "x", "name": "X", "widgets": ["cpu", "noSuchModule"]}
        """.utf8))
        #expect(preset.widgets == [.cpu])
    }
}

struct DockFolderMenuTests {
    private let mail = DockApp(path: "/Applications/Mail.app", name: "Mail")
    private let notes = DockApp(path: "/Applications/Notes.app", name: "Notes")

    @Test func aNewFolderTakesTheAppsPlace() {
        let folder = AppFolder(name: "New", apps: [mail])
        let items = DockLayout.replacing(mail, with: folder, in: [.app(notes), .app(mail)])
        #expect(items == [.app(notes), .folder(folder)])
    }

    @Test func anEmptyFolderIsRemovedAndAFullOneStays() {
        let empty = AppFolder(name: "Empty", apps: [])
        let full = AppFolder(name: "Full", apps: [mail])
        let items = DockLayout.addingFolder(empty, to: [.folder(full)])
        #expect(items.count == 2)
        #expect(DockLayout.removingEmptyFolders(from: items) == [.folder(full)])
    }

    @Test func listsFoldersInOrder() {
        var dock = DockSettings()
        let first = AppFolder(name: "A", apps: [])
        let second = AppFolder(name: "B", apps: [])
        dock.items = [.folder(first), .app(mail), .folder(second)]
        #expect(dock.folders == [first, second])
    }
}
