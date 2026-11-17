import GlassWorkCore

/// Rows of To-Dos, Keep Awake and Timers.
extension ModuleOptionSpec {
    static var dayToDay: [ModuleOptionSpec] {
        typealias Key = ItemOption
        return [
            option(
                .timers, Key.timerSound, "Sound", "Звук",
                .choice([
                    OptionChoice(TimerAlert.noSound, "No sound"),
                    OptionChoice("Glass", "Glass"),
                    OptionChoice("Hero", "Hero"),
                    OptionChoice("Ping", "Ping (sound)"),
                    OptionChoice("Purr", "Purr"),
                    OptionChoice("Submarine", "Submarine"),
                ]),
                fallback: TimerAlert.defaultSound
            ),
            toggle(
                .timers, Key.timerNotifies, "Notify when a timer ends", "Уведомлять, когда таймер закончится",
                fallback: true
            ),
            option(
                .keepAwake, Key.keepAwakeMinutes, "Default duration", "Длительность по умолчанию",
                .choice([
                    OptionChoice("0", "Until turned off"),
                    OptionChoice("15", "15 min"),
                    OptionChoice("60", "1 hour"),
                    OptionChoice("120", "2 hours"),
                    OptionChoice("300", "5 hours"),
                ]),
                fallback: "0"
            ),
            option(
                .keepAwake, Key.keepAwakeBatteryFloor, "Stop on battery below", "Выключать на батарее ниже",
                .choice([
                    OptionChoice("0", "Never"),
                    OptionChoice("10", "10%"),
                    OptionChoice("20", "20%"),
                    OptionChoice("30", "30%"),
                ]),
                fallback: "20"
            ),
            option(
                .todos, Key.todoSort, "Sort", "Сортировка",
                .choice([
                    OptionChoice(TodoSort.manual.rawValue, "Manual"),
                    OptionChoice(TodoSort.dueDate.rawValue, "Due date"),
                    OptionChoice(TodoSort.title.rawValue, "Title"),
                ]),
                fallback: TodoSort.manual.rawValue
            ),
            option(
                .todos, Key.todoCompleted, "Completed items", "Выполненные",
                .choice([
                    OptionChoice(CompletedTodos.hide.rawValue, "Hide at once"),
                    OptionChoice(CompletedTodos.day.rawValue, "Hide after 1 day"),
                    OptionChoice(CompletedTodos.week.rawValue, "Hide after 1 week"),
                ]),
                fallback: CompletedTodos.hide.rawValue
            ),
            toggle(.todos, Key.todoGroupsByList, "Group by list", "Группировать по спискам", fallback: true),
            option(
                .todos, Key.todoDefaultFilter, "Default filter", "Фильтр по умолчанию",
                .choice([
                    OptionChoice(TodoFilter.all.rawValue, "All"),
                    OptionChoice(TodoFilter.today.rawValue, "Today"),
                    OptionChoice(TodoFilter.overdue.rawValue, "Overdue"),
                    OptionChoice(TodoFilter.flagged.rawValue, "Flagged"),
                ]),
                fallback: TodoFilter.all.rawValue
            ),
            option(
                .todos, Key.todoCountMode, "Count in the menu bar", "Считать в строке меню",
                .choice([
                    OptionChoice(TodoCountMode.open.rawValue, "Open items"),
                    OptionChoice(TodoCountMode.dueToday.rawValue, "Due today"),
                    OptionChoice(TodoCountMode.overdue.rawValue, "Overdue"),
                ]),
                fallback: TodoCountMode.open.rawValue
            ),
            toggle(
                .todos, Key.todoIncludesUndated, "Include items without a date", "Включать задачи без даты",
                fallback: true
            ),
        ]
    }
}
