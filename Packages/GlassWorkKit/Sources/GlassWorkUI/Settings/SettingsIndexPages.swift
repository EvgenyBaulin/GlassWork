import GlassWorkCore
import SwiftUI

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
                "widgets.photoSubfolders",
                "Include subfolders",
                "Включая вложенные папки",
                .widgets,
                ["Widgets", "Photo Frame"]
            ),
            page("widgets.photoOrder", "Order", "Порядок", .widgets, ["Widgets", "Photo Frame"]),
            page("widgets.photoSize", "Photo size", "Размер фото", .widgets, ["Widgets", "Photo Frame"]),
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
            page(
                "hiding.alwaysHidden",
                "Always-hidden section",
                "Всегда скрытая секция",
                .menuBar,
                ["Menu Bar", "Hiding"]
            ),
            page("hiding.hover", "Show on hover", "Показывать при наведении", .menuBar, ["Menu Bar", "Hiding"]),
            page(
                "shortcut.hiddenBar",
                "Show hidden menu bar items",
                "Показать скрытые значки строки меню",
                .shortcuts,
                ["Shortcuts"]
            ),
            page(
                "shortcut.searchMenuBar",
                "Search menu bar items",
                "Поиск по значкам строки меню",
                .shortcuts,
                ["Shortcuts"]
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
            page("widgets.system", "System widgets", "Системные виджеты", .widgets, ["Widgets"]),
            page(
                "widgets.screenTime",
                "Screen Time",
                "Экранное время",
                .widgets,
                ["Widgets"],
                keywords: ["tracking", "учёт"]
            ),
            page(
                "widgets.refresh",
                "Refresh widgets every",
                "Обновлять виджеты каждые",
                .widgets,
                ["Widgets"],
                keywords: ["interval", "интервал"]
            ),
            page("widgets.reloadAll", "Reload All Widgets", "Перезагрузить все виджеты", .widgets, ["Widgets"]),
            page("widgets.dayStart", "Day starts at", "День начинается в", .widgets, ["Widgets", "Screen Time"]),
            page(
                "widgets.excludedApps",
                "Apps not counted",
                "Не учитывать приложения",
                .widgets,
                ["Widgets", "Screen Time"],
                keywords: ["exclude", "исключить"]
            ),
            page(
                "widgets.resetScreenTime",
                "Reset Data…",
                "Сбросить данные…",
                .widgets,
                ["Widgets", "Screen Time"],
                keywords: ["delete", "удалить"]
            ),
            page(
                "widgets.wordOfDay",
                "Word of the Day",
                "Слово дня",
                .widgets,
                ["Widgets"],
                keywords: ["dictionary", "словарь"]
            ),
            page(
                "widgets.git",
                "Git widget",
                "Виджет Git",
                .widgets,
                ["Widgets"],
                keywords: ["repository", "репозиторий"]
            ),
            page(
                "widgets.gitRepositories",
                "Repositories",
                "Репозитории",
                .widgets,
                ["Widgets", "Git widget"]
            ),
            page("widgets.gitToDo", "Counts as to do", "Считать задачей", .widgets, ["Widgets", "Git widget"]),
            page(
                "appearance.followSun",
                "Follow sunrise and sunset",
                "Следовать за восходом и закатом",
                .module(.appearance),
                ["Menu Bar", "Appearance"],
                keywords: ["dark", "тёмная", "night", "ночь"]
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
