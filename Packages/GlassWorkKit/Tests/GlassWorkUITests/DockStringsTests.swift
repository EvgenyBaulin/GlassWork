import Foundation
import GlassWorkCore
@testable import GlassWorkUI
import Testing

/// A key missing from the catalog comes back as the key itself, which would put "Folder Utilities" in the Dock.
struct DockStringsTests {
    @Test(arguments: [
        ("Utilities", "Utilities"),
        ("Dev Tools", "Dev Tools"),
        ("Office", "Office"),
        ("Study", "Study"),
    ])
    func presetFoldersHaveTheirNames(name: String, title: String) {
        #expect(DockPresets.folderTitle(name) == title)
    }

    @Test(arguments: DockPresetID.allCases)
    func everyBuiltInHasATitle(id: DockPresetID) {
        let preset = DockPreset(id: id.rawValue, name: id.rawValue, widgets: [])
        #expect(!preset.title.hasPrefix("Preset "))
    }

    @Test func theOwnersPresetKeepsItsName() {
        #expect(DockPreset(id: UUID().uuidString, name: "Mine", widgets: []).title == "Mine")
    }

    @Test(arguments: DockPosition.allCases)
    func positionsHaveTitles(position: DockPosition) {
        #expect(!position.title.hasPrefix("Dock position"))
    }

    @Test func aStackStyleIsNotTheCoolingFan() {
        #expect(DockStackStyle.fan.title == "Fan")
        #expect(DockStackStyle.grid.title == "Grid")
    }
}
