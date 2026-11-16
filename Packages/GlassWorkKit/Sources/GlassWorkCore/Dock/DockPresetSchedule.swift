import Foundation

/// From a time on given days, the Dock uses a preset, or none.
public struct DockPresetRule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Nil turns presets off.
    public var presetID: String?
    /// `Calendar` weekdays: 1 is Sunday, 7 is Saturday.
    public var weekdays: Set<Int>
    /// Minutes after midnight.
    public var minute: Int

    public init(id: UUID = UUID(), presetID: String?, weekdays: Set<Int> = Set(1 ... 7), minute: Int) {
        self.id = id
        self.presetID = presetID
        self.weekdays = weekdays
        self.minute = minute
    }
}

/// Which rule is in force. Pure, so the clock and the calendar come in.
public enum DockPresetSchedule {
    /// The rule that started last, looking back up to a week, and when it started. A rule from yesterday evening
    /// still holds this morning until today's first one starts.
    public static func current(
        at date: Date,
        rules: [DockPresetRule],
        calendar: Calendar = .current
    ) -> (rule: DockPresetRule, start: Date)? {
        let today = calendar.startOfDay(for: date)
        for back in 0 ... 7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let started = rules.compactMap { rule -> (DockPresetRule, Date)? in
                guard rule.weekdays.contains(weekday),
                      let start = calendar.date(byAdding: .minute, value: rule.minute, to: day),
                      start <= date
                else { return nil }
                return (rule, start)
            }
            if let latest = started.max(by: { $0.1 < $1.1 }) {
                return latest
            }
        }
        return nil
    }
}

public extension DockPresets {
    /// Leaves presets: widgets and the folders a preset brought go, and changes made to the one in use are kept
    /// with it, as when switching. Apps, the owner's own folders and stacks stay.
    static func turnOff(current: DockPreset?, in dock: inout DockSettings) {
        apply(DockPreset(id: "", name: "", widgets: []), current: current, to: &dock)
        dock.activePreset = nil
    }
}
