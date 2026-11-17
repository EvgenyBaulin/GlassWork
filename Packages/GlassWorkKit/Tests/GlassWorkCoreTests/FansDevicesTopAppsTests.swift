import Foundation
@testable import GlassWorkCore
import Testing

struct SeparateCurveSaveTests {
    @Test func saveAsGivesTheNewCurveToTheFanBeingEdited() {
        var settings = FanSettings()
        settings.separateCurves = true
        settings.fanPresetIDs = ["balanced", "silent"]
        settings.applyEdit(FanPreset.performance.curve)

        settings.saveCurve(as: "Mine", id: "mine", forFan: 1)

        #expect(settings.fanPresetIDs == ["balanced", "mine"])
        #expect(settings.selectedPresetID == "mine")
        #expect(settings.curve(forFan: 1, isOnAC: true) == FanPreset.performance.curve)
        // The other fan keeps its own curve instead of following the new selection.
        #expect(settings.curve(forFan: 0, isOnAC: true) == FanPreset.balanced.curve)
    }

    @Test func withoutSeparateCurvesNothingIsAssigned() {
        var settings = FanSettings()
        settings.fanPresetIDs = ["balanced", "silent"]
        settings.saveCurve(as: "Mine", id: "mine", forFan: 1)
        #expect(settings.fanPresetIDs == ["balanced", "silent"])
    }

    @Test func aFanThatDoesNotExistIsIgnored() {
        var settings = FanSettings()
        settings.separateCurves = true
        settings.fanPresetIDs = ["balanced"]
        settings.saveCurve(as: "Mine", id: "mine", forFan: 3)
        #expect(settings.fanPresetIDs == ["balanced"])
        #expect(settings.selectedPresetID == "mine")
    }

    @Test func deletingAPointKeepsTheMinimum() {
        var curve = FanPreset.balanced.curve
        while let smaller = curve.removing(0) {
            curve = smaller
        }
        #expect(curve.points.count == FanCurve.pointLimit.lowerBound)
        #expect(curve.removing(0) == nil)
    }
}

struct FansWidgetPresetTests {
    @Test func theSnapshotCarriesTheUsersCurvesAndTheActiveOne() throws {
        var settings = FanSettings()
        settings.saveCurve(as: "Quiet Studio", id: "quiet")
        var state = WidgetFanState(
            presets: settings.presets.map { WidgetFanState.Preset(id: $0.id, name: $0.name) },
            selectedPresetID: settings.selectedPresetID
        )
        state.control = .ready

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WidgetFanState.self, from: data)

        #expect(decoded.presets.last == WidgetFanState.Preset(id: "quiet", name: "Quiet Studio"))
        #expect(decoded.selectedPreset?.name == "Quiet Studio")
        #expect(decoded.presets.count == FanPreset.builtIn.count + 1)
    }
}

struct DeviceSelectionTests {
    private let devices = [
        DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.2),
        DeviceBattery(name: "Keyboard", kind: .keyboard, charge: 0.8),
    ]

    @Test func everyDeviceCountsByDefault() {
        let selection = DeviceSelection()
        #expect(selection.filter(devices) == devices)
        #expect(selection.includes("A device not seen yet"))
    }

    @Test func anUntickedDeviceIsLeftOut() {
        let value = DeviceSelection().stored(after: "Mouse", isIncluded: false)
        let selection = DeviceSelection(options: [ItemOption.excludedDevices: value])
        #expect(selection.filter(devices).map(\.name) == ["Keyboard"])
        #expect(selection.includes("New headphones"))
    }

    @Test func tickingAgainBringsItBack() {
        let both = DeviceSelection(options: [ItemOption.excludedDevices: "Keyboard\nMouse"])
        let value = both.stored(after: "Mouse", isIncluded: true)
        #expect(value == "Keyboard")
        #expect(DeviceSelection(options: [ItemOption.excludedDevices: value]).includes("Mouse"))
    }

    @Test func aNameWithACommaSurvives() {
        let name = "Evgeny's AirPods, Pro"
        let value = DeviceSelection().stored(after: name, isIncluded: false)
        #expect(DeviceSelection(options: [ItemOption.excludedDevices: value]).excluded == [name])
    }

    @Test func seenDevicesAreRememberedOnceEach() throws {
        let first = try #require(DeviceSelection().recording(devices))
        let selection = DeviceSelection(options: [ItemOption.seenDevices: first])
        #expect(selection.seen == ["Mouse", "Keyboard"])
        #expect(selection.recording(devices) == nil)
        let more = devices + [DeviceBattery(name: "Pods", kind: .headphones, charge: 0.5)]
        #expect(DeviceSelection(options: [ItemOption.seenDevices: first]).recording(more) == "Mouse\nKeyboard\nPods")
    }
}

struct TopAppsOptionsTests {
    private var snapshot: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 0))
        snapshot.apps = [
            ProcessUsage(pid: 1, name: "Browser", cpu: 12, memory: 900),
            ProcessUsage(pid: 2, name: "Editor", cpu: 30, memory: 300),
            ProcessUsage(pid: 3, name: "Mail", cpu: 1, memory: 600),
            ProcessUsage(pid: 4, name: "Music", cpu: 5, memory: 100),
        ]
        return snapshot
    }

    @Test func ranksByCPUOrByMemory() {
        let byCPU = TopAppsOptions(ranking: .cpu).ranked(snapshot, limit: 3)
        #expect(byCPU.map(\.name) == ["Editor", "Browser", "Music"])
        let byMemory = TopAppsOptions(ranking: .memory).ranked(snapshot, limit: 3)
        #expect(byMemory.map(\.name) == ["Browser", "Mail", "Editor"])
    }

    @Test func readsTheChoicesAndIgnoresNonsense() {
        let chosen = TopAppsOptions(options: [ItemOption.topAppsRanking: "memory", ItemOption.topAppsCount: "8"])
        #expect(chosen == TopAppsOptions(ranking: .memory, count: 8))
        let odd = TopAppsOptions(options: [ItemOption.topAppsRanking: "disk", ItemOption.topAppsCount: "7"])
        #expect(odd == TopAppsOptions())
    }

    @Test func theCountFollowsTheSizeUnlessChosen() {
        let automatic = TopAppsOptions()
        #expect(automatic.limit(for: .small) == 4)
        #expect(automatic.limit(for: .large) == 10)
        let three = TopAppsOptions(count: 3)
        #expect(three.limit(for: .medium) == 3)
        #expect(three.limit(for: .extraLarge) == 3)
        let eight = TopAppsOptions(count: 8)
        // Small and medium only have room for four rows.
        #expect(eight.limit(for: .medium) == 4)
        #expect(eight.limit(for: .large) == 8)
    }

    @Test func anOldSnapshotDecodesWithoutTheOptions() throws {
        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["topAppsOptions"] == nil)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded.topAppsOptions == nil)

        var withOptions = snapshot
        withOptions.topAppsOptions = TopAppsOptions(ranking: .memory, count: 5)
        let round = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(withOptions))
        #expect(round.topAppsOptions == TopAppsOptions(ranking: .memory, count: 5))
    }
}
