import GlassWorkCore

/// Rows of Eject and Dev Servers.
extension ModuleOptionSpec {
    static var toolRows: [ModuleOptionSpec] {
        typealias Key = ItemOption
        typealias Developer = DeveloperOptions.Key
        return [
            toggle(
                .eject, Key.ejectAsksFirst, "Ask before Eject All", "Спрашивать перед «Извлечь все»", fallback: true
            ),
            toggle(.eject, Key.ejectIncludesImages, "Include disk images", "Показывать образы дисков", fallback: true),
            toggle(
                .eject, Key.ejectIncludesNetwork, "Include network volumes", "Показывать сетевые диски",
                fallback: false
            ),
            option(
                .eject, Key.ejectNever, "Never eject", "Никогда не извлекать",
                .text(placeholder: "Time Machine, Backup"), fallback: ""
            ),
            option(
                .devServers, Developer.devServerPorts, "Port range", "Диапазон портов",
                .text(placeholder: "3000-9999"), fallback: ""
            ),
            option(
                .devServers, Developer.devServerSeconds, "Update every", "Обновлять каждые",
                .choice([OptionChoice("5", "5 s"), OptionChoice("10", "10 s"), OptionChoice("30", "30 s")]),
                fallback: "30"
            ),
            toggle(
                .devServers, Key.countsServices, "Count databases as services", "Считать базы данных сервисами",
                fallback: true
            ),
            option(
                .devServers, Developer.devServerIgnore, "Ignore", "Не показывать",
                .text(placeholder: "5432, postgres"), fallback: ""
            ),
        ]
    }
}
