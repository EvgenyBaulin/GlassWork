import Foundation

/// The order of `AppSettings.modules`, which the menu bar, the Hub and Settings all follow.
public extension AppSettings {
    /// One step of a list drag. `visible` is what the list shows, in order; the offsets count within it.
    /// Modules the list leaves out keep their places, so an unavailable module cannot end up between groups.
    mutating func reorderModules(_ visible: [ModuleID], from source: IndexSet, to destination: Int) {
        let slots = modules.indices.filter { visible.contains(modules[$0].id) }
        var rows = slots.map { modules[$0] }
        guard rows.count == visible.count, source.allSatisfy(rows.indices.contains) else { return }
        let moved = source.map { rows[$0] }
        let target = destination - source.count(in: 0 ..< min(destination, rows.count))
        for index in source.reversed() {
            rows.remove(at: index)
        }
        rows.insert(contentsOf: moved, at: min(max(target, 0), rows.count))
        for (slot, row) in zip(slots, rows) {
            modules[slot] = row
        }
    }

    /// Puts `module` in the place of `target`. Modules stay in their group, so a drop on another group is ignored.
    mutating func moveModule(_ module: ModuleID, to target: ModuleID) {
        guard module != target, module.group == target.group,
              let source = modules.firstIndex(where: { $0.id == module }),
              let destination = modules.firstIndex(where: { $0.id == target })
        else { return }
        modules.insert(modules.remove(at: source), at: destination)
    }

    /// True when modules that stay in the bar changed places. A module coming or going is not a reorder:
    /// it must not undo the places the user gave the others with ⌘-drag.
    static func isReordered(from old: [ModuleID], to new: [ModuleID]) -> Bool {
        let kept = Set(old).intersection(new)
        return old.filter(kept.contains) != new.filter(kept.contains)
    }

    /// The order of a new install. Modes, styles and options stay as they are.
    mutating func resetModuleOrder() {
        let rank = Dictionary(uniqueKeysWithValues: ModuleID.allCases.enumerated().map { ($1, $0) })
        modules.sort { rank[$0.id, default: .max] < rank[$1.id, default: .max] }
    }
}
