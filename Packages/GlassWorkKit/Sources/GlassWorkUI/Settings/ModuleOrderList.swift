import GlassWorkCore
import SwiftUI

public extension DisplayStyle {
    var title: String {
        switch self {
        case .symbol: loc("Symbol")
        case .figure: loc("Figure")
        case .graph: loc("Graph")
        case .graphAndFigure: loc("Graph and figure")
        case .labelled: loc("Labelled")
        }
    }
}

/// In menu bar, Hub only or Off.
public struct ModePicker: View {
    private let module: ModuleID
    private let store: SettingsStore

    public init(module: ModuleID, store: SettingsStore) {
        self.module = module
        self.store = store
    }

    public var body: some View {
        Picker("", selection: Binding(
            get: { store.settings.module(module)?.mode ?? .off },
            set: { value in store.update { $0.update(module) { $0.mode = value } } }
        )) {
            Text(loc("In menu bar")).tag(ModuleMode.menuBar)
            Text(loc("Hub only")).tag(ModuleMode.hubOnly)
            Text(loc("Off")).tag(ModuleMode.off)
        }
        .labelsHidden()
    }
}

/// Every module by group, for a `List`. A row drags within its group, like the tiles in the Hub.
public struct ModuleOrderSections: View {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        ForEach(ModuleGroup.allCases, id: \.self) { group in
            let rows = store.settings.modules.filter { $0.id.isAvailable && $0.id.group == group }
            if !rows.isEmpty {
                Section(group.title) {
                    ForEach(rows) { setting in
                        ModuleOrderRow(setting: setting, store: store)
                    }
                    .onMove { source, destination in
                        let visible = rows.map(\.id)
                        store.update { $0.reorderModules(visible, from: source, to: destination) }
                    }
                }
            }
        }
    }
}

struct ModuleOrderRow: View {
    let setting: ModuleSettings
    let store: SettingsStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            ModuleIcon(setting.id, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(setting.id.title)
                Text(verbatim: setting.mode == .menuBar ? setting.style.title : "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ModePicker(module: setting.id, store: store).frame(width: 150)
        }
        .padding(.vertical, 2)
    }
}
