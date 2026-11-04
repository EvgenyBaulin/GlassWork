import GlassWorkCore
import SwiftUI

/// Large panel with every enabled module as a live tile.
public struct HubView: View {
    private let monitor: SystemMonitor
    private let store: SettingsStore
    @State private var query = ""
    @State private var selected: ModuleID?
    @State private var isEditing = false
    @Environment(\.panelActions) private var actions

    public init(monitor: SystemMonitor, store: SettingsStore) {
        self.monitor = monitor
        self.store = store
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

    private var modules: [ModuleSettings] {
        store.settings.modules.filter { setting in
            setting.id.isAvailable && (isEditing || setting.mode != .off) && matches(setting.id)
        }
    }

    private func matches(_ module: ModuleID) -> Bool {
        query.isEmpty || module.title.localizedCaseInsensitiveContains(query)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("GlassWork").font(.system(size: 15, weight: .semibold))
                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            TextField(loc("Search"), text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button(isEditing ? loc("Done") : loc("Edit")) { isEditing.toggle() }
        }
        .padding(16)
    }

    private var summary: String {
        let all = store.settings.modules.filter(\.id.isAvailable)
        let inBar = all.filter { $0.mode == .menuBar }.count
        let hubOnly = all.filter { $0.mode == .hubOnly }.count
        return loc("\(inBar) in menu bar · \(hubOnly) Hub only")
    }

    @ViewBuilder
    private var grid: some View {
        let visible = modules
        if visible.isEmpty {
            ContentUnavailableView.search(text: query).frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ModuleGroup.allCases, id: \.self) { group in
                        section(group, modules: visible.filter { $0.id.group == group })
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
                Text(group.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(modules) { setting in tile(setting) }
                }
            }
        }
    }

    private func tile(_ setting: ModuleSettings) -> some View {
        HubTile(setting: setting, monitor: monitor, isEditing: isEditing) {
            if isEditing {
                store.update { $0.update(setting.id) { $0.mode = $0.mode == .off ? .hubOnly : .off } }
            } else {
                selected = setting.id
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(loc("⌃⌥Space opens the Hub")).foregroundStyle(.tertiary)
            Spacer()
            Button(loc("Settings…")) { actions.openSettings(.overview) }.buttonStyle(.plain)
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

/// One module in the Hub: name, live figure and a small graph.
struct HubTile: View {
    let setting: ModuleSettings
    let monitor: SystemMonitor
    let isEditing: Bool
    let action: () -> Void

    var body: some View {
        let content = ItemContent.content(setting.id, monitor: monitor, style: .compact)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ModuleIcon(setting.id, size: 20)
                    Text(setting.id.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    badge
                }
                HStack(alignment: .bottom) {
                    Text(content.text(for: .figure))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    if let values = content.graphValues(monitor) {
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
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
            .contentShape(.rect(cornerRadius: 12))
            .opacity(setting.mode == .off ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var badge: some View {
        if isEditing {
            Image(systemName: setting.mode == .off ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(setting.mode == .off ? Palette.green : Palette.red)
        } else if setting.mode == .hubOnly {
            Text(loc("Hub only"))
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}
