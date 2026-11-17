import GlassWorkCore

/// Rows of the AI Usage module.
extension ModuleOptionSpec {
    static var usageRows: [ModuleOptionSpec] {
        [
            option(
                .aiUsage, AIUsageOption.window, "Window", "Период",
                .choice([
                    OptionChoice(AIUsageWindowChoice.both.rawValue, "Both"),
                    OptionChoice(AIUsageWindowChoice.highest.rawValue, "Highest"),
                    OptionChoice(AIUsageWindowChoice.fiveHour.rawValue, "5 hours"),
                    OptionChoice(AIUsageWindowChoice.week.rawValue, "This week"),
                ]),
                fallback: AIUsageWindowChoice.both.rawValue
            ),
            option(
                .aiUsage, AIUsageOption.warnPercent, "Warn at (share)", "Предупреждать от",
                .number(50 ... 100, step: 5, unit: "%"),
                fallback: String(AIUsageOption.defaultWarnPercent)
            ),
            toggle(
                .aiUsage,
                AIUsageOption.notifyAtWarning,
                "Notify at warning",
                "Уведомлять о предупреждении",
                fallback: true
            ),
            option(
                .aiUsage, AIUsageOption.menuBarTool, "Menu bar tool", "Инструмент в строке меню",
                .choice(
                    [OptionChoice(AIUsageOption.highestTool, "Highest")]
                        + AITool.allCases.map { OptionChoice($0.rawValue, $0.title) }
                ),
                fallback: AIUsageOption.highestTool
            ),
        ] + AITool.allCases.map { tool in
            toggle(.aiUsage, AIUsageOption.enabledKey(tool), tool.title, tool.title, fallback: true)
        }
    }
}
