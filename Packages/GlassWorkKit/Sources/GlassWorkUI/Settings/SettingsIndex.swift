import GlassWorkCore
import SwiftUI

/// A page of the Settings window.
public enum SettingsDestination: Hashable, Sendable {
    case general, menuBar, widgets, dock, fans, windowTiles, shortcuts, permissions, about
    case module(ModuleID)
}

/// A module's name in both languages, with the other words people use for it.
struct ModuleSearchWords: Sendable {
    let module: ModuleID
    let english: String
    let russian: String
    let keywords: [String]
}

/// A place search can take you.
public struct SettingsResult: Sendable, Identifiable {
    public let setting: SearchableSetting
    public let destination: SettingsDestination
    /// English keys, shown as `Menu Bar › CPU`.
    let path: [String]

    public var id: String {
        setting.id
    }

    public var title: String {
        loc(String.LocalizationValue(setting.english))
    }

    public var breadcrumb: String {
        path.map { loc(String.LocalizationValue($0)) }.joined(separator: " › ")
    }

    /// The module to draw, if the result belongs to one.
    public var module: ModuleID? {
        if case let .module(module) = destination {
            return module
        }
        return nil
    }
}

public enum SettingsIndex {
    /// Everything search knows: the option table, the modules and the rows that are not in the table.
    static let all: [SettingsResult] = modules + options + pages

    /// What the search field shows, leaving out modules this Mac does not have.
    @MainActor
    public static func search(_ query: String) -> [(result: SettingsResult, match: SettingMatch)] {
        let usable = all.filter { $0.module?.isAvailable ?? true }
        let byID = Dictionary(uniqueKeysWithValues: usable.map { ($0.id, $0) })
        return SettingsSearch.matches(query, in: usable.map(\.setting)).compactMap { match in
            byID[match.setting.id].map { ($0, match) }
        }
    }

    private static let moduleWords = ModuleSearchExtras.words + [
        ModuleSearchWords(module: .overview, english: "Overview", russian: "Обзор", keywords: ["summary", "сводка"]),
        ModuleSearchWords(
            module: .cpu,
            english: "CPU",
            russian: "CPU",
            keywords: ["processor", "процессор", "load", "загрузка"]
        ),
        ModuleSearchWords(
            module: .memory,
            english: "Memory",
            russian: "Память",
            keywords: ["RAM", "swap", "своп", "оперативная"]
        ),
        ModuleSearchWords(
            module: .disk,
            english: "Disk",
            russian: "Диск",
            keywords: ["SSD", "storage", "накопитель", "место"]
        ),
        ModuleSearchWords(
            module: .network,
            english: "Network",
            russian: "Сеть",
            keywords: ["internet", "speed", "интернет", "скорость"]
        ),
        ModuleSearchWords(
            module: .battery,
            english: "Battery",
            russian: "Батарея",
            keywords: ["charge", "power", "заряд", "аккумулятор"]
        ),
        ModuleSearchWords(
            module: .gpu,
            english: "GPU",
            russian: "GPU",
            keywords: ["graphics", "графика", "видеокарта"]
        ),
        ModuleSearchWords(
            module: .sensors,
            english: "Sensors",
            russian: "Датчики",
            keywords: ["temperature", "температура", "SMC"]
        ),
        ModuleSearchWords(
            module: .fans,
            english: "Fans",
            russian: "Вентиляторы",
            keywords: ["rpm", "cooling", "обороты", "охлаждение", "кулер"]
        ),
        ModuleSearchWords(module: .uptime, english: "Uptime", russian: "Время работы", keywords: ["boot", "запуск"]),
        ModuleSearchWords(
            module: .git,
            english: "Git",
            russian: "Git",
            keywords: ["repository", "branch", "репозиторий", "ветка"]
        ),
        ModuleSearchWords(
            module: .devServers,
            english: "Dev Servers",
            russian: "Dev-серверы",
            keywords: ["ports", "localhost", "порты", "сервер"]
        ),
        ModuleSearchWords(
            module: .docker,
            english: "Docker",
            russian: "Docker",
            keywords: ["containers", "контейнеры"]
        ),
        ModuleSearchWords(module: .ping, english: "Ping", russian: "Пинг", keywords: ["latency", "задержка"]),
        ModuleSearchWords(module: .vpn, english: "VPN", russian: "VPN", keywords: ["tunnel", "туннель"]),
        ModuleSearchWords(
            module: .wifi,
            english: "Wi-Fi",
            russian: "Wi-Fi",
            keywords: ["wireless", "signal", "сигнал", "вайфай"]
        ),
        ModuleSearchWords(
            module: .worldClocks,
            english: "World Clocks",
            russian: "Мировые часы",
            keywords: ["time zones", "часовые пояса"]
        ),
        ModuleSearchWords(module: .timers, english: "Timers", russian: "Таймеры", keywords: ["pomodoro", "помодоро"]),
        ModuleSearchWords(
            module: .keepAwake,
            english: "Keep Awake",
            russian: "Не спать",
            keywords: ["sleep", "caffeine", "сон"]
        ),
        ModuleSearchWords(
            module: .nowPlaying,
            english: "Now Playing",
            russian: "Сейчас играет",
            keywords: ["music", "lyrics", "музыка", "песня"]
        ),
        ModuleSearchWords(module: .notes, english: "Notes", russian: "Заметки", keywords: ["заметка"]),
        ModuleSearchWords(
            module: .countdown,
            english: "Countdown",
            russian: "Обратный отсчёт",
            keywords: ["dates", "даты"]
        ),
        ModuleSearchWords(module: .stopwatch, english: "Stopwatch", russian: "Секундомер", keywords: ["lap", "круг"]),
        ModuleSearchWords(
            module: .shelf,
            english: "Shelf",
            russian: "Полка",
            keywords: ["files", "drag", "drop", "файлы", "перетаскивание"]
        ),
        ModuleSearchWords(
            module: .colours,
            english: "Colours",
            russian: "Цвета",
            keywords: ["colors", "picker", "пипетка", "HEX"]
        ),
        ModuleSearchWords(
            module: .appearance,
            english: "Appearance",
            russian: "Оформление",
            keywords: ["dark mode", "тёмная тема"]
        ),
        ModuleSearchWords(
            module: .eject,
            english: "Eject",
            russian: "Извлечь",
            keywords: ["volumes", "тома", "флешка"]
        ),
        ModuleSearchWords(
            module: .sunMoon,
            english: "Sun and Moon",
            russian: "Солнце и Луна",
            keywords: ["sunrise", "sunset", "восход", "закат"]
        ),
        ModuleSearchWords(module: .date, english: "Date", russian: "Дата", keywords: ["week", "неделя", "календарь"]),
        ModuleSearchWords(
            module: .deviceBatteries,
            english: "Device Batteries",
            russian: "Заряд устройств",
            keywords: ["AirPods", "mouse", "мышь", "наушники"]
        ),
        ModuleSearchWords(
            module: .calendar,
            english: "Calendar",
            russian: "Календарь",
            keywords: ["events", "события", "calendars", "календари", "birthdays", "дни рождения"]
        ),
        ModuleSearchWords(module: .endsIn, english: "Ends In", russian: "До конца", keywords: ["meeting", "встреча"]),
        ModuleSearchWords(module: .todos, english: "To-Dos", russian: "Задачи", keywords: ["reminders", "напоминания"]),
        ModuleSearchWords(
            module: .weather,
            english: "Weather",
            russian: "Погода",
            keywords: ["forecast", "city", "прогноз", "город"]
        ),
        ModuleSearchWords(
            module: .rates,
            english: "Rates",
            russian: "Курсы",
            keywords: ["currency", "bitcoin", "валюта", "доллар"]
        ),
        ModuleSearchWords(
            module: .clipboard,
            english: "Clipboard",
            russian: "Буфер обмена",
            keywords: ["paste", "history", "вставка", "история"]
        ),
    ]

    private static var modules: [SettingsResult] {
        moduleWords.map { words in
            SettingsResult(
                setting: SearchableSetting(
                    id: "module.\(words.module.rawValue)",
                    english: words.english,
                    russian: words.russian,
                    keywords: words.keywords
                ),
                destination: .module(words.module),
                path: ["Menu Bar", words.english]
            )
        }
    }

    private static var options: [SettingsResult] {
        ModuleOptionSpec.all.map { spec in
            let module = spec.module.flatMap { id in moduleWords.first { $0.module == id } }
            let choices: [String] = if case let .choice(list) = spec.kind {
                list.map(\.title)
            } else {
                []
            }
            return SettingsResult(
                setting: SearchableSetting(
                    id: spec.id,
                    english: spec.title,
                    russian: spec.russian,
                    keywords: [module?.english, module?.russian].compactMap(\.self) + choices
                ),
                destination: spec.module.map(SettingsDestination.module) ?? .menuBar,
                path: ["Menu Bar", module?.english ?? "Hub"]
            )
        }
    }
}

public extension EnvironmentValues {
    /// The option a search result opened, so its row can stand out and Advanced can open for it.
    @Entry var settingsHighlight: String?
}
