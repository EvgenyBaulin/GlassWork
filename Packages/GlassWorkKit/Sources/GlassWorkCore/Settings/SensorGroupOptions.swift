import Foundation

/// Which sensor groups the Sensors panel lists. Everything shows until the user hides a group.
public struct SensorGroupOptions: Sendable, Equatable {
    private var hidden: Set<SensorGroup>

    public init() {
        hidden = []
    }

    public init(options: [String: String]) {
        var names = Set((options[ItemOption.hiddenSensorGroups] ?? "")
            .split(separator: ",")
            .compactMap { SensorGroup(rawValue: String($0)) })
        // The older "include unknown sensors" switch keeps hiding Other.
        if !options.flag(ItemOption.showsUnknownSensors, default: true) {
            names.insert(.other)
        }
        hidden = names
    }

    public func shows(_ group: SensorGroup) -> Bool {
        !hidden.contains(group)
    }

    /// The groups to list, in their usual order.
    public var shownGroups: [SensorGroup] {
        SensorGroup.allCases.filter(shows)
    }

    /// Writes one group's choice into `options`. Defaults are removed, so nothing is stored while all show.
    public static func set(_ group: SensorGroup, isShown: Bool, in options: inout [String: String]) {
        var current = SensorGroupOptions(options: options)
        if isShown {
            current.hidden.remove(group)
        } else {
            current.hidden.insert(group)
        }
        // Other keeps its own flag, which older settings files already use.
        let listed = SensorGroup.allCases.filter { $0 != .other && current.hidden.contains($0) }
        options[ItemOption.hiddenSensorGroups] = listed.isEmpty ? nil : listed.map(\.rawValue).joined(separator: ",")
        options[ItemOption.showsUnknownSensors] = current.shows(.other) ? nil : "false"
    }
}
