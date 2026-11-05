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
            keywords: ["events", "события"]
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

/// Rows that are not in the option table.
extension SettingsIndex {
    static var pages: [SettingsResult] {
        func page(
            _ id: String,
            _ english: String,
            _ russian: String,
            _ destination: SettingsDestination,
            _ path: [String],
            keywords: [String] = []
        ) -> SettingsResult {
            SettingsResult(
                setting: SearchableSetting(id: id, english: english, russian: russian, keywords: keywords),
                destination: destination,
                path: path
            )
        }
        return [
            page("widgets.photoFrame", "Photo Frame", "Фоторамка", .widgets, ["Widgets"], keywords: ["photos", "фото"]),
            page(
                "widgets.onThisDay",
                "On This Day",
                "В этот день",
                .widgets,
                ["Widgets"],
                keywords: ["photos", "фото"]
            ),
            page(
                "widgets.birthdays",
                "Birthdays",
                "Дни рождения",
                .widgets,
                ["Widgets"],
                keywords: ["contacts", "контакты"]
            ),
            page(
                "widgets.askFirst",
                "Ask before running",
                "Спрашивать перед запуском",
                .widgets,
                ["Widgets", "Commands"]
            ),
            page(
                "sunMoon.place",
                "Location",
                "Место",
                .module(.sunMoon),
                ["Menu Bar", "Sun and Moon"],
                keywords: ["city", "город"]
            ),
            page("shortcut.hub", "Open the Hub", "Открыть Хаб", .shortcuts, ["Shortcuts"]),
            page("shortcut.quickPaste", "Clipboard history", "История буфера обмена", .shortcuts, ["Shortcuts"]),
            page(
                "shortcut.textCapture",
                "Copy text from screen",
                "Скопировать текст с экрана",
                .shortcuts,
                ["Shortcuts"]
            ),
            page("shortcut.quickQuit", "Quit an app", "Завершить приложение", .shortcuts, ["Shortcuts"]),
            page(
                "general.log",
                "Keep diagnostic log",
                "Вести журнал диагностики",
                .general,
                ["General"],
                keywords: ["log", "debug", "журнал", "отладка"]
            ),
            page("page.general", "General", "Основные", .general, ["General"], keywords: ["общие", "настройки"]),
            page(
                "page.menuBar",
                "Menu Bar",
                "Строка меню",
                .menuBar,
                ["Menu Bar"],
                keywords: ["modules", "модули", "order", "порядок"]
            ),
            page("page.widgets", "Widgets", "Виджеты", .widgets, ["Widgets"]),
            page("page.dock", "Dock", "Dock", .dock, ["Dock"], keywords: ["док"]),
            page("page.fans", "Fans", "Вентиляторы", .fans, ["Fans"], keywords: ["rpm", "обороты", "кулер", "helper"]),
            page("page.curves", "Curves", "Кривые", .fans, ["Fans", "Curves"], keywords: ["кривая", "fan curve"]),
            page(
                "page.control",
                "Control",
                "Управление",
                .fans,
                ["Fans", "Control"],
                keywords: ["вентилятор", "Max", "Auto"]
            ),
            page(
                "page.tiles",
                "Window Tiles",
                "Раскладка окон",
                .windowTiles,
                ["Window Tiles"],
                keywords: ["windows", "окна", "snap"]
            ),
            page(
                "page.shortcuts",
                "Shortcuts",
                "Сочетания клавиш",
                .shortcuts,
                ["Shortcuts"],
                keywords: ["hotkeys", "keyboard", "горячие клавиши"]
            ),
            page(
                "page.permissions",
                "Permissions",
                "Разрешения",
                .permissions,
                ["Permissions"],
                keywords: ["privacy", "доступ", "конфиденциальность"]
            ),
            page(
                "page.about",
                "About",
                "О программе",
                .about,
                ["About"],
                keywords: ["version", "версия", "license", "лицензия"]
            ),
            page(
                "general.login",
                "Launch at login",
                "Запускать при входе",
                .general,
                ["General"],
                keywords: ["startup", "автозапуск"]
            ),
            page(
                "general.figures",
                "Menu bar figures",
                "Цифры в строке меню",
                .general,
                ["General"],
                keywords: ["numbers", "compact", "precise"]
            ),
            page(
                "general.alerts", "Notify about low battery and high temperature",
                "Сообщать о низком заряде и перегреве",
                .general, ["General"], keywords: ["notifications", "уведомления"]
            ),
            page(
                "general.export",
                "Export…",
                "Экспорт…",
                .general,
                ["General"],
                keywords: ["JSON", "backup", "резервная копия"]
            ),
            page("general.import", "Import…", "Импорт…", .general, ["General"], keywords: ["JSON", "restore"]),
            page("general.reset", "Reset all…", "Сбросить всё…", .general, ["General"], keywords: ["defaults"]),
            page(
                "general.reveal",
                "Reveal in Finder",
                "Показать в Finder",
                .general,
                ["General"],
                keywords: ["settings.json"]
            ),
            page(
                "hiding.separator",
                "Hide items behind a separator",
                "Прятать значки за разделителем",
                .menuBar,
                ["Menu Bar", "Hiding"]
            ),
            page("menuBar.resetOrder", "Reset order", "Сбросить порядок", .menuBar, ["Menu Bar"]),
            page("menuBar.defaults", "Restore defaults", "Вернуть по умолчанию", .menuBar, ["Menu Bar"]),
            page("menuBar.allHub", "All to Hub", "Всё в Хаб", .menuBar, ["Menu Bar"]),
            page("menuBar.allBar", "All to menu bar", "Всё в строку меню", .menuBar, ["Menu Bar"]),
            page("menuBar.allOff", "All off", "Выключить все", .menuBar, ["Menu Bar"]),
            page("dock.use", "Use GlassWork Dock", "Использовать Dock GlassWork", .dock, ["Dock"]),
            page("dock.iconSize", "Icon size", "Размер значков", .dock, ["Dock"]),
            page("dock.magnification", "Magnification", "Увеличение", .dock, ["Dock"]),
            page("dock.magnified", "Magnified size", "Размер при увеличении", .dock, ["Dock"]),
            page("widgets.desktop", "Live desktop widgets", "Живые виджеты на столе", .widgets, ["Widgets"]),
            page("widgets.system", "System widgets", "Системные виджеты", .widgets, ["Widgets"]),
            page(
                "widgets.screenTime",
                "Screen Time",
                "Экранное время",
                .widgets,
                ["Widgets"],
                keywords: ["tracking", "учёт"]
            ),
            page("widgets.commands", "Commands", "Команды", .widgets, ["Widgets"], keywords: ["scripts", "скрипты"]),
            page("widgets.endpoints", "Endpoints", "Адреса", .widgets, ["Widgets"], keywords: ["URL", "сайты"]),
            page("tiles.use", "Use Window Tiles", "Включить раскладку окон", .windowTiles, ["Window Tiles"]),
            page(
                "tiles.preview",
                "Show a short preview",
                "Показывать, куда встанет окно",
                .windowTiles,
                ["Window Tiles"]
            ),
            page(
                "weather.location", "Use current location", "Использовать геопозицию",
                .module(.weather), ["Menu Bar", "Weather"], keywords: ["GPS"]
            ),
            page(
                "rates.mono", "Monochrome day change in the menu bar", "Изменение за день без цвета в строке меню",
                .module(.rates), ["Menu Bar", "Rates"]
            ),
            page(
                "clipboard.history",
                "Keep a clipboard history",
                "Вести историю буфера обмена",
                .module(.clipboard),
                ["Menu Bar", "Clipboard"]
            ),
            page(
                "clipboard.paste",
                "Paste on click",
                "Вставлять по клику",
                .module(.clipboard),
                ["Menu Bar", "Clipboard"]
            ),
            page(
                "clipboard.exclude", "Never record from these apps", "Не записывать из этих приложений",
                .module(.clipboard), ["Menu Bar", "Clipboard"], keywords: ["passwords", "пароли"]
            ),
            page(
                "nowPlaying.idle",
                "Hide when nothing is playing",
                "Скрывать, когда ничего не играет",
                .module(.nowPlaying),
                ["Menu Bar", "Now Playing"]
            ),
            page(
                "nowPlaying.lyrics",
                "Find lyrics online",
                "Искать тексты в интернете",
                .module(.nowPlaying),
                ["Menu Bar", "Now Playing"]
            ),
            page(
                "nowPlaying.width",
                "Max width",
                "Наибольшая ширина",
                .module(.nowPlaying),
                ["Menu Bar", "Now Playing"]
            ),
            page("ping.host", "Host", "Сервер", .module(.ping), ["Menu Bar", "Ping"], keywords: ["сервер"]),
        ]
    }
}

public extension EnvironmentValues {
    /// The option a search result opened, so its row can stand out and Advanced can open for it.
    @Entry var settingsHighlight: String?
}
