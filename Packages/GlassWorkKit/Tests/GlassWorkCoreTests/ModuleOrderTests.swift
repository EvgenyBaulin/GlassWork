import Foundation
@testable import GlassWorkCore
import Testing

struct ModuleOrderTests {
    private func ids(_ settings: AppSettings, _ group: ModuleGroup) -> [ModuleID] {
        settings.modules.map(\.id).filter { $0.group == group }
    }

    @Test func dragsARowDown() {
        var settings = AppSettings()
        settings.reorderModules([.overview, .cpu, .memory, .disk], from: [0], to: 3)
        #expect(Array(settings.modules.map(\.id).prefix(4)) == [.cpu, .memory, .overview, .disk])
    }

    @Test func dragsARowUp() {
        var settings = AppSettings()
        settings.reorderModules([.overview, .cpu, .memory, .disk], from: [3], to: 1)
        #expect(Array(settings.modules.map(\.id).prefix(4)) == [.overview, .disk, .cpu, .memory])
    }

    @Test func dragsSeveralRowsToTheEnd() {
        var settings = AppSettings()
        settings.reorderModules([.overview, .cpu, .memory, .disk], from: [0, 2], to: 4)
        #expect(Array(settings.modules.map(\.id).prefix(4)) == [.cpu, .disk, .overview, .memory])
    }

    @Test func aRowDroppedOnItsOwnPlaceStays() {
        var settings = AppSettings()
        let before = settings.modules
        settings.reorderModules([.overview, .cpu, .memory], from: [1], to: 2)
        #expect(settings.modules == before)
    }

    @Test func modulesTheListLeavesOutKeepTheirPlaces() {
        var settings = AppSettings()
        settings.reorderModules([.overview, .memory], from: [0], to: 2)
        #expect(Array(settings.modules.map(\.id).prefix(3)) == [.memory, .cpu, .overview])
    }

    @Test func aStaleDragChangesNothing() {
        var settings = AppSettings()
        let before = settings.modules
        settings.reorderModules([.overview, .cpu], from: [5], to: 0)
        #expect(settings.modules == before)
    }

    @Test func aTileTakesThePlaceOfTheOneItLandsOn() {
        var settings = AppSettings()
        settings.moveModule(.overview, to: .memory)
        #expect(Array(settings.modules.map(\.id).prefix(3)) == [.cpu, .memory, .overview])
        settings.moveModule(.overview, to: .cpu)
        #expect(Array(settings.modules.map(\.id).prefix(3)) == [.overview, .cpu, .memory])
    }

    @Test func aModuleStaysInItsGroup() {
        var settings = AppSettings()
        let before = settings.modules
        settings.moveModule(.cpu, to: .git)
        #expect(settings.modules == before)
    }

    @Test func movingKeepsEverythingElseAboutTheModule() {
        var settings = AppSettings()
        settings.update(.cpu) { $0.options["key"] = "value" }
        settings.moveModule(.cpu, to: .disk)
        #expect(settings.module(.cpu)?.options["key"] == "value")
        #expect(settings.module(.cpu)?.mode == .menuBar)
    }

    @Test func resetRestoresTheOrderOnly() {
        var settings = AppSettings()
        settings.update(.gpu) { $0.mode = .menuBar }
        settings.moveModule(.overview, to: .sensors)
        settings.resetModuleOrder()
        #expect(settings.modules.map(\.id) == ModuleID.allCases)
        #expect(settings.module(.gpu)?.mode == .menuBar)
    }

    @Test func theOrderSurvivesTheFile() throws {
        let file = SettingsFile(url: temporaryFolder().appending(path: "settings.json"))
        var settings = AppSettings()
        settings.moveModule(.disk, to: .overview)
        try file.save(settings)
        #expect(try file.load()?.modules.map(\.id) == settings.modules.map(\.id))
    }

    @Test func aChangeOfPlacesIsAReorder() {
        #expect(AppSettings.isReordered(from: [.cpu, .memory], to: [.memory, .cpu]))
    }

    @Test func aModuleComingOrGoingIsNotAReorder() {
        #expect(!AppSettings.isReordered(from: [.cpu, .memory], to: [.cpu, .disk, .memory]))
        #expect(!AppSettings.isReordered(from: [.cpu, .disk, .memory], to: [.cpu, .memory]))
        #expect(!AppSettings.isReordered(from: [], to: [.cpu, .memory]))
    }
}
