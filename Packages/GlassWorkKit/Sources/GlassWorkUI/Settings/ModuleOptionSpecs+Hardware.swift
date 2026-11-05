import GlassWorkCore

/// Rows that choose how the Mac's hardware is read and shown.
extension ModuleOptionSpec {
    static var hardware: [ModuleOptionSpec] {
        typealias Key = ItemOption
        typealias Developer = DeveloperOptions.Key
        return [
            option(
                .sensors, Key.temperatureUnit, "Temperature units", "Единицы температуры",
                .choice([
                    OptionChoice(TemperatureUnit.system.rawValue, "System"),
                    OptionChoice(TemperatureUnit.celsius.rawValue, "°C"),
                    OptionChoice(TemperatureUnit.fahrenheit.rawValue, "°F"),
                ]),
                fallback: TemperatureUnit.system.rawValue
            ),
            option(.network, Key.networkInterface, "Interface", "Интерфейс", .live(.networkInterfaces), fallback: ""),
            option(.gpu, Key.gpuName, "GPU", "GPU", .live(.gpus), fallback: ""),
            option(.disk, Key.volumePath, "Disk", "Диск", .live(.volumes), fallback: ""),
            option(
                .ping, Developer.pingInterval, "Interval", "Как часто",
                .choice([
                    OptionChoice("10", "10 s"),
                    OptionChoice("30", "30 s"),
                    OptionChoice("60", "1 min"),
                ]),
                fallback: "30"
            ),
            option(
                .ping, Developer.pingTimeout, "Timeout (ping)", "Ждать ответ",
                .choice([OptionChoice("1", "1 s"), OptionChoice("2", "2 s"), OptionChoice("5", "5 s")]),
                fallback: "2"
            ),
        ]
    }
}
