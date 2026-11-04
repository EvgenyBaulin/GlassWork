import GlassWorkCore
import SwiftUI

/// One choice in a picker row.
public struct OptionChoice: Sendable, Equatable {
    public let value: String
    /// English text, which is also the key in the string catalog.
    public let title: String

    init(_ value: String, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// A list only the Mac can fill in, so it is read when the row appears.
public enum LiveOptionSource: Sendable, Equatable {
    case networkInterfaces, gpus, volumes

    /// English text for the empty value, which leaves the choice to the Mac.
    var automaticTitle: String {
        self == .volumes ? "Startup disk" : "Automatic"
    }

    /// Names of real things, which need no translation.
    func choices() -> [OptionChoice] {
        switch self {
        case .networkInterfaces: NetworkReader.interfaces().map { OptionChoice($0.name, $0.title) }
        case .gpus: GPUReader.samples().map { OptionChoice($0.name, $0.name) }
        case .volumes: DiskReader.volumes().map { OptionChoice($0.path, $0.name) }
        }
    }
}

public enum OptionKind: Sendable, Equatable {
    case toggle
    case choice([OptionChoice])
    case live(LiveOptionSource)
    case number(ClosedRange<Int>, step: Int, unit: String)
    case text(placeholder: String)
}

/// A setting that has a row in Settings. Rows and search both come from this table, so anything search finds
/// is a real control, and every entry here has code behind it.
public struct ModuleOptionSpec: Sendable, Identifiable {
    /// Nil for the Hub, which has no module of its own.
    public let module: ModuleID?
    public let key: String
    /// English text, which is also the key in the string catalog.
    public let title: String
    /// The Russian title. Search looks at both languages, whatever the app's language is.
    public let russian: String
    public let kind: OptionKind
    public let isAdvanced: Bool
    public let read: @Sendable (AppSettings) -> String
    public let write: @Sendable (inout AppSettings, String) -> Void

    public var id: String {
        "\(module?.rawValue ?? "hub").\(key)"
    }

    public var localizedTitle: String {
        loc(String.LocalizationValue(title))
    }
}

// swiftlint:disable function_parameter_count
/// A row that stores into `ModuleSettings.options` and removes the entry again at the default.
func option(
    _ module: ModuleID,
    _ key: String,
    _ title: String,
    _ russian: String,
    _ kind: OptionKind,
    fallback: String,
    isAdvanced: Bool = false
) -> ModuleOptionSpec {
    ModuleOptionSpec(
        module: module,
        key: key,
        title: title,
        russian: russian,
        kind: kind,
        isAdvanced: isAdvanced,
        read: { $0.module(module)?.options[key] ?? fallback },
        write: { settings, value in
            settings.update(module) { $0.options[key] = value == fallback ? nil : value }
        }
    )
}

func toggle(
    _ module: ModuleID,
    _ key: String,
    _ title: String,
    _ russian: String,
    fallback: Bool,
    isAdvanced: Bool = false
) -> ModuleOptionSpec {
    option(module, key, title, russian, .toggle, fallback: String(fallback), isAdvanced: isAdvanced)
}

private func percent(
    _ module: ModuleID,
    _ key: String,
    _ title: String,
    _ russian: String,
    fallback: Int,
    isAdvanced: Bool = false
) -> ModuleOptionSpec {
    let kind = OptionKind.number(5 ... 100, step: 5, unit: "%")
    return option(module, key, title, russian, kind, fallback: String(fallback), isAdvanced: isAdvanced)
}

private func hub(
    _ key: String,
    _ title: String,
    _ russian: String,
    _ kind: OptionKind,
    read: @escaping @Sendable (HubSettings) -> String,
    write: @escaping @Sendable (inout HubSettings, String) -> Void
) -> ModuleOptionSpec {
    ModuleOptionSpec(
        module: nil,
        key: key,
        title: title,
        russian: russian,
        kind: kind,
        isAdvanced: false,
        read: { read($0.hub) },
        write: { write(&$0.hub, $1) }
    )
}

// swiftlint:enable function_parameter_count

public extension ModuleOptionSpec {
    static let all: [ModuleOptionSpec] = system + hardware + everyday + developer + hubRows

    static func rows(for module: ModuleID) -> [ModuleOptionSpec] {
        all.filter { $0.module == module }
    }

    static var hubOptions: [ModuleOptionSpec] {
        all.filter { $0.module == nil }
    }

    private static var system: [ModuleOptionSpec] {
        typealias Key = ItemOption
        let temperature = OptionKind.number(60 ... 110, step: 5, unit: "°C")
        return [
            toggle(.overview, Key.showsCPU, "Show CPU", "Показывать процессор", fallback: true),
            toggle(.overview, Key.showsMemory, "Show memory", "Показывать память", fallback: true),
            toggle(.overview, Key.showsDisk, "Show disk", "Показывать диск", fallback: false),
            toggle(.cpu, Key.splitsUserSystem, "Split user / system", "Разделять польз. и систему", fallback: true),
            option(
                .cpu, Key.topApps, "Top apps in panel", "Приложений в панели",
                .number(1 ... 10, step: 1, unit: ""), fallback: "4"
            ),
            option(
                .cpu, Key.samplingSeconds, "Sampling interval", "Частота опроса",
                .choice([OptionChoice("1", "1 s"), OptionChoice("2", "2 s"), OptionChoice("5", "5 s")]),
                fallback: "2", isAdvanced: true
            ),
            toggle(
                .cpu, Key.slowsOnBattery, "On battery: poll 2× slower (Low Power 4×)",
                "На батарее опрашивать в 2 раза реже (режим энергосбережения — в 4)",
                fallback: true, isAdvanced: true
            ),
            numberStyle,
            percent(.cpu, Key.highlightAbove, "Highlight above", "Выделять выше", fallback: 80, isAdvanced: true),
            option(
                .memory, Key.memoryFigure, "Show as", "Показывать как",
                .choice([
                    OptionChoice(MemoryFigure.share.rawValue, "Share"),
                    OptionChoice(MemoryFigure.gigabytes.rawValue, "GB"),
                    OptionChoice(MemoryFigure.pressure.rawValue, "Pressure"),
                ]),
                fallback: MemoryFigure.share.rawValue
            ),
            toggle(.memory, Key.showsSwap, "Show swap in panel", "Показывать своп в панели", fallback: true),
            toggle(.memory, Key.colorsByPressure, "Colour by pressure", "Цвет по давлению памяти", fallback: true),
            option(
                .disk, Key.diskFigure, "Show", "Показывать",
                .choice([
                    OptionChoice(DiskFigure.free.rawValue, "Free space"),
                    OptionChoice(DiskFigure.activity.rawValue, "Read / write"),
                    OptionChoice(DiskFigure.both.rawValue, "Both"),
                ]),
                fallback: DiskFigure.free.rawValue
            ),
            option(
                .network, Key.rateUnit, "Units", "Единицы",
                .choice([
                    OptionChoice(RateUnit.bytes.rawValue, "Bytes/s"),
                    OptionChoice(RateUnit.bits.rawValue, "Bits/s"),
                ]),
                fallback: RateUnit.bytes.rawValue
            ),
            option(
                .network, Key.networkDirection, "Direction", "Направление",
                .choice([
                    OptionChoice(NetworkDirection.both.rawValue, "Both"),
                    OptionChoice(NetworkDirection.download.rawValue, "Down (speed)"),
                    OptionChoice(NetworkDirection.upload.rawValue, "Up (speed)"),
                ]),
                fallback: NetworkDirection.both.rawValue
            ),
            option(
                .network, Key.hideBelow, "Hide below", "Скрывать ниже",
                .choice([
                    OptionChoice("0", "Never"),
                    OptionChoice("10000", "10 KB/s"),
                    OptionChoice("100000", "100 KB/s"),
                    OptionChoice("1000000", "1 MB/s"),
                ]),
                fallback: "0"
            ),
            option(
                .battery, Key.batteryFigure, "Show", "Показывать",
                .choice([
                    OptionChoice(BatteryFigure.charge.rawValue, "Charge"),
                    OptionChoice(BatteryFigure.timeLeft.rawValue, "Time left"),
                ]),
                fallback: BatteryFigure.charge.rawValue
            ),
            toggle(
                .battery,
                Key.hidesWhenFull,
                "Hide when fully charged",
                "Скрывать при полном заряде",
                fallback: false
            ),
            lowBattery,
            option(.sensors, Key.warnAbove, "Warn above", "Предупреждать выше", temperature, fallback: "95"),
            toggle(
                .sensors, Key.showsUnknownSensors, "Include unknown sensors (Other)",
                "Показывать неизвестные датчики (Прочие)", fallback: true, isAdvanced: true
            ),
            notifyTemperature,
            option(
                .uptime, Key.uptimeFormat, "Format", "Формат",
                .choice([
                    OptionChoice(UptimeFormat.compact.rawValue, "3d 4h"),
                    OptionChoice(UptimeFormat.days.rawValue, "3 days"),
                    OptionChoice(UptimeFormat.hours.rawValue, "76:12"),
                ]),
                fallback: UptimeFormat.compact.rawValue
            ),
        ]
    }

    private static var everyday: [ModuleOptionSpec] {
        typealias Key = ItemOption
        return [
            option(
                .calendar, Key.calendarWindowHours, "Show events starting within", "События в ближайшие",
                .choice([
                    OptionChoice("1", "1 hour"),
                    OptionChoice("4", "4 hours"),
                    OptionChoice("8", "8 hours"),
                    OptionChoice("24", "24 hours"),
                    OptionChoice("0", "Any time"),
                ]),
                fallback: "4"
            ),
            toggle(
                .calendar,
                Key.skipsAllDay,
                "Skip all-day events",
                "Пропускать события на весь день",
                fallback: true
            ),
            option(
                .calendar, Key.titleLength, "Title length", "Длина названия",
                .number(10 ... 40, step: 5, unit: ""), fallback: "20"
            ),
            toggle(
                .endsIn, Key.includesAllDay, "Include all-day events", "Учитывать события на весь день",
                fallback: false
            ),
            option(
                .endsIn, Key.warnMinutes, "Warn at", "Предупреждать за",
                .number(2 ... 30, step: 1, unit: "min"), fallback: "5"
            ),
            toggle(.endsIn, Key.showsFree, "Show “Free” when no event is on", "Показывать «Свободно»", fallback: true),
            toggle(.timers, Key.showsSeconds, "Show seconds", "Показывать секунды", fallback: true),
            option(
                .timers, Key.timerPresets, "Preset lengths, in minutes", "Длительности, в минутах",
                .text(placeholder: "1, 5, 10, 25, 60"), fallback: ""
            ),
            toggle(
                .keepAwake, Key.letsDisplaySleep, "Let the display sleep", "Разрешить экрану засыпать",
                fallback: false
            ),
            option(
                .notes, Key.panelSize, "Panel size", "Размер панели",
                .choice([
                    OptionChoice(PanelSize.small.rawValue, "Small"),
                    OptionChoice(PanelSize.medium.rawValue, "Medium (size)"),
                    OptionChoice(PanelSize.large.rawValue, "Large"),
                ]),
                fallback: PanelSize.medium.rawValue
            ),
            option(
                .notes, Key.notesFont, "Font", "Шрифт",
                .choice([
                    OptionChoice(NotesFont.system.rawValue, "System"),
                    OptionChoice(NotesFont.mono.rawValue, "Mono"),
                ]),
                fallback: NotesFont.system.rawValue
            ),
            toggle(.todos, Key.hidesWhenDone, "Hide when all are done", "Скрывать, когда всё сделано", fallback: true),
            option(
                .colours, Key.colourFormat, "Copy as", "Копировать как",
                .choice([
                    OptionChoice(ColourFormat.hex.rawValue, "HEX"),
                    OptionChoice(ColourFormat.rgb.rawValue, "RGB"),
                    OptionChoice(ColourFormat.hsl.rawValue, "HSL"),
                ]),
                fallback: ColourFormat.hex.rawValue
            ),
            toggle(.colours, Key.colourUppercase, "Uppercase", "Заглавные буквы", fallback: true),
            toggle(.colours, Key.colourHash, "Include #", "Добавлять #", fallback: true),
            option(
                .colours, Key.colourLimit, "Remember", "Запоминать",
                .number(4 ... 50, step: 2, unit: ""), fallback: "12"
            ),
            option(
                .sunMoon, Key.sunShows, "Show", "Показывать",
                .choice([
                    OptionChoice(SunShows.next.rawValue, "Next sunrise or sunset"),
                    OptionChoice(SunShows.sunrise.rawValue, "Sunrise"),
                    OptionChoice(SunShows.sunset.rawValue, "Sunset"),
                ]),
                fallback: SunShows.next.rawValue
            ),
            percent(.deviceBatteries, Key.warnBelow, "Warn below", "Предупреждать ниже", fallback: 20),
            option(
                .date, Key.dateFigure, "Format", "Формат",
                .choice([
                    OptionChoice(DateFigure.weekdayDayMonth.rawValue, "Weekday, day, month"),
                    OptionChoice(DateFigure.dayMonth.rawValue, "Day, month"),
                    OptionChoice(DateFigure.numeric.rawValue, "Numbers"),
                    OptionChoice(DateFigure.custom.rawValue, "Custom"),
                ]),
                fallback: DateFigure.weekdayDayMonth.rawValue
            ),
            option(
                .date, Key.datePattern, "Custom format", "Свой формат",
                .text(placeholder: "EEE d MMM"), fallback: ""
            ),
            toggle(.date, Key.showsWeek, "Show week number", "Показывать номер недели", fallback: false),
            option(
                .date, Key.weekNumbering, "Week numbering", "Нумерация недель",
                .choice([
                    OptionChoice(WeekNumbering.iso.rawValue, "ISO 8601"),
                    OptionChoice(WeekNumbering.system.rawValue, "System"),
                ]),
                fallback: WeekNumbering.iso.rawValue
            ),
        ]
    }

    private static var developer: [ModuleOptionSpec] {
        typealias Key = ItemOption
        return [
            toggle(
                .git, DeveloperOptions.Key.autoDiscover, "Auto-discover in ~/Developer", "Искать в ~/Developer сами",
                fallback: true
            ),
            option(
                .git, DeveloperOptions.Key.searchDepth, "Search depth", "Глубина поиска",
                .choice([OptionChoice("1", "1 level"), OptionChoice("2", "2 levels")]), fallback: "2"
            ),
            option(
                .docker, Key.dockerCount, "Count", "Считать",
                .choice([
                    OptionChoice(DockerCount.running.rawValue, "Running (containers)"),
                    OptionChoice(DockerCount.all.rawValue, "All"),
                ]),
                fallback: DockerCount.running.rawValue
            ),
            option(
                .ping, Key.warnMilliseconds, "Warn above", "Предупреждать выше",
                .number(50 ... 1000, step: 50, unit: "ms"), fallback: "150"
            ),
            toggle(
                .vpn, Key.onlyWhenConnected, "Show only when connected", "Показывать только при подключении",
                fallback: false
            ),
            toggle(.vpn, Key.greenWhenConnected, "Green when connected", "Зелёный при подключении", fallback: true),
            option(
                .wifi, Key.weakSignal, "Weak signal below", "Слабый сигнал ниже",
                .number(-90 ... -50, step: 5, unit: "dBm"), fallback: "-75"
            ),
        ]
    }

    private static var hubRows: [ModuleOptionSpec] {
        [
            hub(
                "grouping", "Grouping", "Группировка",
                .choice([OptionChoice("true", "By category"), OptionChoice("false", "None")]),
                read: { String($0.isGrouped) },
                write: { $0.isGrouped = $1 == "true" }
            ),
            hub(
                "tileSize", "Tile size", "Размер плиток",
                .choice([
                    OptionChoice(PanelSize.small.rawValue, "Small"),
                    OptionChoice(PanelSize.medium.rawValue, "Medium (size)"),
                    OptionChoice(PanelSize.large.rawValue, "Large"),
                ]),
                read: { $0.tileSize.rawValue },
                write: { $0.tileSize = PanelSize(rawValue: $1) ?? .medium }
            ),
            hub(
                "showsMenuBarModules", "Also show modules that are in the menu bar",
                "Показывать и модули из строки меню", .toggle,
                read: { String($0.showsMenuBarModules) },
                write: { $0.showsMenuBarModules = $1 == "true" }
            ),
        ]
    }

    /// Lives in General too: it applies to every figure in the menu bar.
    private static var numberStyle: ModuleOptionSpec {
        ModuleOptionSpec(
            module: .cpu,
            key: "numberStyle",
            title: "Numbers in menu bar",
            russian: "Числа в строке меню",
            kind: .choice([
                OptionChoice(NumberStyle.compact.rawValue, "Compact"),
                OptionChoice(NumberStyle.precise.rawValue, "Exact"),
            ]),
            isAdvanced: true,
            read: { $0.numberStyle.rawValue },
            write: { $0.numberStyle = NumberStyle(rawValue: $1) ?? .compact }
        )
    }

    /// One figure for both the item's colour and the notification.
    private static var lowBattery: ModuleOptionSpec {
        ModuleOptionSpec(
            module: .battery,
            key: ItemOption.lowPercent,
            title: "Low battery warning",
            russian: "Предупреждение о низком заряде",
            kind: .number(5 ... 50, step: 5, unit: "%"),
            isAdvanced: false,
            read: { String($0.alerts.lowBatteryPercent) },
            write: { settings, value in
                settings.alerts.lowBatteryPercent = Int(value) ?? settings.alerts.lowBatteryPercent
                settings.update(.battery) { $0.options[ItemOption.lowPercent] = value }
            }
        )
    }

    private static var notifyTemperature: ModuleOptionSpec {
        ModuleOptionSpec(
            module: .sensors,
            key: "notifyAt",
            title: "Notify at",
            russian: "Уведомлять при",
            kind: .number(60 ... 110, step: 5, unit: "°C"),
            isAdvanced: true,
            read: { String($0.alerts.highTemperature) },
            write: { settings, value in
                settings.alerts.highTemperature = Int(value) ?? settings.alerts.highTemperature
            }
        )
    }
}
