import GlassWorkCore
import SwiftUI

/// Large panel with every enabled module as a live tile.
public struct HubView: View {
    private let monitor: SystemMonitor
    private let store: SettingsStore
    @State private var query = ""
    @State private var selected: ModuleID?
    @State private var isEditing: Bool
    /// Inline, not a popover: a click in another window counts as a click outside the panel and closes it.
    @State private var isAddingModules: Bool
    @Environment(\.panelActions) private var actions

    public init(monitor: SystemMonitor, store: SettingsStore) {
        self.init(monitor: monitor, store: store, isEditing: false)
    }

    init(monitor: SystemMonitor, store: SettingsStore, isEditing: Bool, isAddingModules: Bool = false) {
        self.monitor = monitor
        self.store = store
        _isEditing = State(initialValue: isEditing)
        _isAddingModules = State(initialValue: isAddingModules)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let selected {
                detail(selected)
            } else {
                header
                Divider()
                grid
                footer
            }
        }
        .frame(width: 700, height: 640)
    }

    private var available: [ModuleSettings] {
        store.settings.modules.filter(\.id.isAvailable)
    }

    private var modules: [ModuleSettings] {
        let showsBar = store.settings.hub.showsMenuBarModules
        return available.filter { setting in
            setting.mode != .off && (showsBar || setting.mode != .menuBar) && matches(setting.id)
        }
    }

    private var columns: [GridItem] {
        let count = switch store.settings.hub.tileSize {
        case .small: 5
        case .medium: 4
        case .large: 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var offModules: [ModuleSettings] {
        available.filter { $0.mode == .off }
    }

    private func matches(_ module: ModuleID) -> Bool {
        query.isEmpty || module.title.localizedCaseInsensitiveContains(query)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("GlassWork").font(.system(size: 15, weight: .semibold))
                Text(isEditing ? loc("Editing · drag ⋮⋮ to reorder · (−) turns a module off") : summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isEditing {
                Button(loc("Done")) { setEditing(false) }
                    .buttonStyle(.borderedProminent)
            } else {
                TextField(loc("Search"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Button {
                    actions.openSettings(.overview)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(loc("Settings…"))
            }
        }
        .padding(16)
    }

    private func setEditing(_ value: Bool) {
        isEditing = value
        isAddingModules = false
        query = ""
    }

    private var summary: String {
        let inBar = available.filter { $0.mode == .menuBar }.count
        let hubOnly = available.filter { $0.mode == .hubOnly }.count
        return loc("\(inBar) in menu bar · \(hubOnly) Hub only")
    }

    @ViewBuilder
    private var grid: some View {
        let visible = modules
        if visible.isEmpty, !isEditing {
            ContentUnavailableView.search(text: query).frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if query.isEmpty, !isEditing {
                        RunningAppsBlock(apps: monitor.apps.apps)
                    }
                    if isEditing, isAddingModules {
                        addModules
                    }
                    if store.settings.hub.isGrouped {
                        ForEach(ModuleGroup.allCases, id: \.self) { group in
                            section(group, modules: visible.filter { $0.id.group == group })
                        }
                    } else {
                        tiles(visible)
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func section(_ group: ModuleGroup, modules: [ModuleSettings]) -> some View {
        if !modules.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.title.uppercased())
                    Spacer()
                    Text(verbatim: "\(modules.count)").foregroundStyle(.tertiary)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                tiles(modules)
            }
        }
    }

    private func tiles(_ modules: [ModuleSettings]) -> some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(modules.enumerated()), id: \.element.id) { index, setting in
                tile(setting, index: index)
            }
        }
    }

    @ViewBuilder
    private func tile(_ setting: ModuleSettings, index: Int) -> some View {
        if isEditing {
            HubEditTile(
                setting: setting,
                monitor: monitor,
                tilt: index.isMultiple(of: 2) ? -1.1 : 1.1,
                turnOff: { store.update { $0.update(setting.id) { $0.mode = .off } } },
                move: { dragged in store.update { $0.moveModule(dragged, to: setting.id) } }
            )
        } else {
            HubTile(setting: setting, monitor: monitor) { selected = setting.id }
        }
    }

    private var addModules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("Off").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if offModules.isEmpty {
                Text(loc("Every module is on."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 6) {
                ForEach(offModules) { setting in
                    addButton(setting)
                }
            }
        }
    }

    private func addButton(_ setting: ModuleSettings) -> some View {
        Button {
            store.update { $0.update(setting.id) { $0.mode = .hubOnly } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Palette.green)
                ModuleIcon(setting.id, size: 20)
                Text(setting.id.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(verbatim: "⌃⌥Space")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.12), in: .rect(cornerRadius: 4))
            Text(loc("opens the Hub from anywhere · click the GlassWork icon also works"))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            if isEditing {
                Button(loc("\(offModules.count) off · + Add modules…")) { isAddingModules.toggle() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            } else {
                Button(loc("Edit")) { setEditing(true) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func detail(_ module: ModuleID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selected = nil
            } label: {
                Label(loc("Hub"), systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .padding([.top, .horizontal], 16)
            ScrollView {
                ModulePanel(module: module, monitor: monitor).frame(maxWidth: .infinity)
            }
        }
    }
}

/// One module in the Hub. A click opens its panel.
struct HubTile: View {
    let setting: ModuleSettings
    let monitor: SystemMonitor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HubTileFace(setting: setting, monitor: monitor)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// A tile in edit mode: tilted, with (−) to turn the module off and ⋮⋮ to drag it within its group.
///
/// The handle sits on top of the tile, not inside a button, so a press on it starts a drag and not a click.
struct HubEditTile: View {
    let setting: ModuleSettings
    let monitor: SystemMonitor
    let tilt: Double
    let turnOff: () -> Void
    let move: (ModuleID) -> Void
    @State private var isTargeted = false

    var body: some View {
        HubTileFace(setting: setting, monitor: monitor, isEditing: true)
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.blue, lineWidth: 2)
                }
            }
            .overlay(alignment: .topLeading) { turnOffButton }
            .overlay(alignment: .topTrailing) { handle }
            .rotationEffect(.degrees(tilt))
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first.flatMap(ModuleID.init(rawValue:)),
                      dragged.group == setting.id.group
                else { return false }
                move(dragged)
                return true
            } isTargeted: { isTargeted = $0 }
    }

    private var turnOffButton: some View {
        Button(action: turnOff) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 16))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(white: 0.3))
        }
        .buttonStyle(.plain)
        .help(loc("Turn off"))
        .offset(x: -6, y: -6)
    }

    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .rotationEffect(.degrees(90))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(.rect)
            .draggable(setting.id.rawValue) {
                HStack(spacing: 6) {
                    ModuleIcon(setting.id, size: 20)
                    Text(setting.id.title).font(.system(size: 12, weight: .medium))
                }
            }
    }
}

/// What a tile shows, with or without edit mode: name, live figure and a small graph.
struct HubTileFace: View {
    let setting: ModuleSettings
    let monitor: SystemMonitor
    /// The edit handle takes the top corner, so the badge moves down next to the figure.
    var isEditing = false

    var body: some View {
        let content = ItemContent.content(setting.id, monitor: monitor, style: .compact, options: setting.options)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ModuleIcon(setting.id, size: 20)
                Text(setting.id.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if !isEditing {
                    badge
                }
            }
            .padding(.trailing, isEditing ? 14 : 0)
            HStack(alignment: .bottom) {
                Text(content.text(for: .figure))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                if isEditing, setting.mode == .hubOnly {
                    badge
                } else if let values = content.graphValues(monitor) {
                    Sparkline(
                        values: values,
                        domain: content.domain,
                        color: content.accent?.color ?? setting.id.tint
                    )
                    .frame(width: 52, height: 26)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    @ViewBuilder
    private var badge: some View {
        if setting.mode == .hubOnly {
            Text(loc("Hub only"))
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}
