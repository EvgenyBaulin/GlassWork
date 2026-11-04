import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// The table is what Settings and search both show, so it has to agree with the string catalog.
struct OptionTableTests {
    /// Russian text by key, straight from the catalog file.
    private static let catalog: [String: String] = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../Sources/GlassWorkUI/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { return [:] }
        return strings.compactMapValues { entry in
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
            let russian = localizations?["ru"] as? [String: Any]
            return (russian?["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }()

    private func russian(_ key: String) -> String? {
        Self.catalog[key]
    }

    @Test func idsAreUnique() {
        let ids = ModuleOptionSpec.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyTitleIsInTheCatalogWithTheSameRussian() {
        #expect(!Self.catalog.isEmpty)
        for spec in ModuleOptionSpec.all {
            #expect(russian(spec.title) == spec.russian, "\(spec.id)")
        }
    }

    /// What each choice must say in Russian. A key can already exist with another meaning: «Down» is a server
    /// that is down, not a download, so checking that a key exists is not enough.
    private static let choiceRussian: [String: String] = [
        "1 MB/s": "1 МБ/с",
        "1 hour": "1 час",
        "1 level": "1 уровень",
        "1 s": "1 с",
        "10 KB/s": "10 КБ/с",
        "100 KB/s": "100 КБ/с",
        "2 levels": "2 уровня",
        "2 s": "2 с",
        "24 hours": "24 часа",
        "3 days": "3 дня",
        "3d 4h": "3д 4ч",
        "4 hours": "4 часа",
        "5 s": "5 с",
        "8 hours": "8 часов",
        "All": "Все",
        "Any time": "Любое время",
        "Bits/s": "Бит/с",
        "Both": "Оба",
        "By category": "По категориям",
        "Bytes/s": "Байт/с",
        "Charge": "Заряд",
        "Compact": "Компактно",
        "Custom": "Свой",
        "Day, month": "Число, месяц",
        "Down (speed)": "Загрузка",
        "Exact": "Точно",
        "Free space": "Свободное место",
        "GB": "ГБ",
        "Large": "Большой",
        "Medium (size)": "Средний",
        "Mono": "Моноширинный",
        "Never": "Никогда",
        "Next sunrise or sunset": "Ближайший восход или закат",
        "None": "Без групп",
        "Numbers": "Числа",
        "Pressure": "Давление",
        "Read / write": "Чтение и запись",
        "Running (containers)": "Запущенные",
        "Share": "Доля",
        "Small": "Маленький",
        "Sunrise": "Восход",
        "Sunset": "Закат",
        "System": "Система",
        "Time left": "Время работы",
        "Up (speed)": "Отдача",
        "Weekday, day, month": "День недели, число, месяц",
    ]

    @Test func everyChoiceSaysWhatItMeans() {
        for spec in ModuleOptionSpec.all {
            guard case let .choice(choices) = spec.kind else { continue }
            for choice in choices where !["ISO 8601", "HEX", "RGB", "HSL", "76:12"].contains(choice.title) {
                #expect(russian(choice.title) == Self.choiceRussian[choice.title], "\(spec.id): \(choice.title)")
            }
        }
    }

    /// Reads the compiled catalog, which hosted test runs do not resolve.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
    func aReusedLabelShowsPlainEnglish() {
        #expect(loc("Down (speed)") == "Down")
        #expect(loc("Up (speed)") == "Up")
        #expect(loc("Medium (size)") == "Medium")
        #expect(loc("Running (containers)") == "Running")
    }

    @Test func everySystemShortcutNameIsTranslated() {
        for known in SystemShortcut.known where !["Spotlight", "Mission Control"].contains(known.name) {
            #expect(russian(known.name) != nil, "\(known.name)")
        }
    }

    @Test func theDefaultIsNeverStored() {
        for spec in ModuleOptionSpec.all where spec.module != nil && spec.key != ItemOption.lowPercent {
            var settings = AppSettings()
            spec.write(&settings, spec.read(settings))
            #expect(settings == AppSettings(), "\(spec.id)")
        }
    }

    @Test func aChoiceReadsBackAsWritten() {
        for spec in ModuleOptionSpec.all {
            guard case let .choice(choices) = spec.kind else { continue }
            for choice in choices {
                var settings = AppSettings()
                spec.write(&settings, choice.value)
                #expect(spec.read(settings) == choice.value, "\(spec.id)")
            }
        }
    }

    @Test func theBatteryLimitMovesTheItemAndTheNotificationTogether() throws {
        let spec = try #require(ModuleOptionSpec.rows(for: .battery).first { $0.key == ItemOption.lowPercent })
        var settings = AppSettings()
        spec.write(&settings, "25")
        #expect(settings.alerts.lowBatteryPercent == 25)
        #expect(settings.module(.battery)?.options[ItemOption.lowPercent] == "25")
        #expect(spec.read(settings) == "25")
    }

    @Test func advancedRowsAreWhereTheDesignPutsThem() {
        let modules = Set(ModuleOptionSpec.all.filter(\.isAdvanced).compactMap(\.module))
        #expect(modules == [.cpu, .sensors])
    }
}

/// What the options do to the menu bar.
@MainActor
struct ItemOptionTests {
    private let memorySample = MemorySample(
        total: 32_000_000_000, app: 10_000_000_000, wired: 2_000_000_000, compressed: 0,
        cached: 0, free: 0, swapUsed: 0, swapTotal: 0, pressure: .warning
    )

    private func battery(charge: Double, charging: Bool = false, onAC: Bool = false) -> BatterySample {
        BatterySample(charge: charge, isCharging: charging, isOnAC: onAC, minutesRemaining: 222)
    }

    @Test func memoryShowsTheChosenFigure() {
        #expect(ItemContent.memory(memorySample, style: .compact, options: [:]).figure == "38%")
        let inGB = [ItemOption.memoryFigure: "gigabytes"]
        #expect(ItemContent.memory(memorySample, style: .compact, options: inGB).figure == "12G")
        let pressure = [ItemOption.memoryFigure: "pressure"]
        #expect(ItemContent.memory(memorySample, style: .compact, options: pressure).figure == loc("Medium"))
    }

    @Test func memoryColoursFollowThePressureUnlessTurnedOff() {
        #expect(ItemContent.memory(memorySample, style: .compact, options: [:]).alert == Palette.orange)
        let off = [ItemOption.colorsByPressure: "false"]
        #expect(ItemContent.memory(memorySample, style: .compact, options: off).alert == nil)
    }

    @Test func networkShowsTheChosenDirection() {
        let sample = NetworkSample(
            download: 2_000_000,
            upload: 500_000,
            interfaces: [],
            sessionReceived: 0,
            sessionSent: 0
        )
        let both = ItemContent.network(sample, style: .compact, options: [:])
        #expect(both.figure == "↓ 2M/s")
        #expect(both.secondLine == "↑ 500K/s")
        let upload = ItemContent.network(sample, style: .compact, options: [ItemOption.networkDirection: "upload"])
        #expect(upload.figure == "↑ 500K/s")
        #expect(upload.secondLine == nil)
    }

    @Test func networkCanCountInBits() {
        let sample = NetworkSample(download: 1_000_000, upload: 0, interfaces: [], sessionReceived: 0, sessionSent: 0)
        let item = ItemContent.network(sample, style: .compact, options: [ItemOption.rateUnit: "bits"])
        #expect(item.figure == "↓ 8Mb/s")
    }

    @Test func aSpeedBelowTheLimitReadsAsADash() {
        let sample = NetworkSample(download: 5000, upload: 50000, interfaces: [], sessionReceived: 0, sessionSent: 0)
        let item = ItemContent.network(sample, style: .compact, options: [ItemOption.hideBelow: "10000"])
        #expect(item.figure == "↓ —")
        #expect(item.secondLine == "↑ 50K/s")
    }

    @Test func batteryCanShowTimeLeft() {
        let item = ItemContent.battery(
            battery(charge: 0.5),
            style: .compact,
            options: [ItemOption.batteryFigure: "timeLeft"]
        )
        #expect(item.figure == "3:42")
    }

    @Test func theBatteryLimitIsTheChosenOne() {
        let limit = [ItemOption.lowPercent: "30"]
        #expect(ItemContent.battery(battery(charge: 0.25), style: .compact, options: limit).alert == Palette.red)
        #expect(ItemContent.battery(battery(charge: 0.25), style: .compact, options: [:]).alert == nil)
    }

    @Test func aFullBatteryOnPowerCanHide() {
        let hide = [ItemOption.hidesWhenFull: "true"]
        #expect(ItemContent.battery(battery(charge: 1, onAC: true), style: .compact, options: hide).isHidden)
        #expect(!ItemContent.battery(battery(charge: 1), style: .compact, options: hide).isHidden)
        #expect(!ItemContent.battery(battery(charge: 1, onAC: true), style: .compact, options: [:]).isHidden)
    }

    @Test func overviewShowsWhatIsTicked() {
        let monitor = SystemMonitor()
        #expect(ItemContent.overview(monitor, options: [:]).figure == "0% 0%")
        let oneOnly = [ItemOption.showsMemory: "false"]
        #expect(ItemContent.overview(monitor, options: oneOnly).figure == "0%")
        #expect(ItemContent.overview(monitor, options: oneOnly).template == "100%")
        let nothing = [ItemOption.showsCPU: "false", ItemOption.showsMemory: "false"]
        #expect(ItemContent.overview(monitor, options: nothing).figure == "—")
    }

    @Test func uptimeFollowsTheFormat() {
        let boot = Date(timeIntervalSince1970: 1_800_000_000)
        let now = boot.addingTimeInterval(76 * 3600 + 12 * 60)
        #expect(ItemContent.uptime(since: boot, now: now, options: [:]).figure == "3d 4h")
        let hours = [ItemOption.uptimeFormat: "hours"]
        #expect(ItemContent.uptime(since: boot, now: now, options: hours).figure == "76:12")
    }

    @Test func timersCanDropTheSeconds() {
        #expect(ItemContent.timers(750, options: [:]).figure == "12:30")
        let item = ItemContent.timers(750, options: [ItemOption.showsSeconds: "false"])
        #expect(item.figure == loc("\(13) min"))
    }

    @Test func endsInCanLeaveTheBarWhenFree() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ItemContent.endsIn([], at: now, options: [:]).figure == loc("Free"))
        #expect(!ItemContent.endsIn([], at: now, options: [:]).isHidden)
        #expect(ItemContent.endsIn([], at: now, options: [ItemOption.showsFree: "false"]).isHidden)
    }

    @Test func endsInWarnsAtTheChosenTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = AgendaEvent(
            id: "1",
            title: "Call",
            start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(500)
        )
        #expect(ItemContent.endsIn([event], at: now, options: [:]).alert == nil)
        let early = [ItemOption.warnMinutes: "10"]
        #expect(ItemContent.endsIn([event], at: now, options: early).alert == Palette.orange)
    }

    @Test func deviceBatteriesShowTheLowest() {
        let devices = [
            DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.8),
            DeviceBattery(name: "Keyboard", kind: .keyboard, charge: 0.15),
        ]
        let item = ItemContent.deviceBatteries(devices, options: [:])
        #expect(item.figure == "15%")
        #expect(item.alert == Palette.red)
        #expect(ItemContent.deviceBatteries(devices, options: [ItemOption.warnBelow: "10"]).alert == nil)
    }

    @Test func dockerCanCountEverything() {
        let containers = [
            DockerContainer(id: "1", name: "web", image: "nginx", status: "Up", isRunning: true, ports: []),
            DockerContainer(id: "2", name: "db", image: "pg", status: "Exited", isRunning: false, ports: []),
        ]
        let reading = DockerReading.containers(containers, context: nil)
        #expect(ItemContent.docker(reading).figure == "1")
        #expect(ItemContent.docker(reading, options: [ItemOption.dockerCount: "all"]).figure == "2")
    }

    @Test func vpnCanHideWhileDisconnected() {
        let reading = VPNReading(services: [], tunnels: [])
        #expect(!ItemContent.vpn(reading).isHidden)
        #expect(ItemContent.vpn(reading, options: [ItemOption.onlyWhenConnected: "true"]).isHidden)
    }

    @Test func onlyTheItemsThatHideGetMeasuredAgain() {
        #expect(ModuleID.battery.canHideItself)
        #expect(ModuleID.vpn.canHideItself)
        #expect(!ModuleID.cpu.canHideItself)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct ModuleOptionSnapshotTests {
    private func store() -> SettingsStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlassWorkRows-\(UUID().uuidString)")
        return SettingsStore(file: SettingsFile(url: folder.appending(path: "settings.json")))
    }

    private func snapshot(_ module: ModuleID, height: CGFloat, name: String, dark: Bool) {
        let view = Form {
            ModuleOptionRows(module: module, store: store(), showsAdvanced: true)
        }
        .formStyle(.grouped)
        .frame(width: 620, height: height)
        snapshotPanel(view, name: name, dark: dark)
    }

    @Test(arguments: [true, false])
    func cpuWithAdvancedOpen(dark: Bool) {
        snapshot(.cpu, height: 420, name: "cpu", dark: dark)
    }

    @Test(arguments: [true, false])
    func sensorsWithAdvancedOpen(dark: Bool) {
        snapshot(.sensors, height: 300, name: "sensors", dark: dark)
    }

    @Test(arguments: [true, false])
    func date(dark: Bool) {
        snapshot(.date, height: 300, name: "date", dark: dark)
    }
}
