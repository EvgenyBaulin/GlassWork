import GlassWorkCore

/// Rows of the AI Usage module.
extension ModuleOptionSpec {
    static var usageRows: [ModuleOptionSpec] {
        [
            option(
                .aiUsage, AIUsageOption.window, "Window", "Период",
                .choice([
                    OptionChoice(AIUsageWindowChoice.highest.rawValue, "Highest"),
                    OptionChoice(AIUsageWindowChoice.fiveHour.rawValue, "5 hours"),
                    OptionChoice(AIUsageWindowChoice.week.rawValue, "This week"),
                ]),
                fallback: AIUsageWindowChoice.highest.rawValue
            ),
            option(
                .aiUsage, AIUsageOption.warnPercent, "Warn at (share)", "Предупреждать от",
                .number(50 ... 100, step: 5, unit: "%"),
                fallback: String(AIUsageOption.defaultWarnPercent)
            ),
        ]
    }
}
