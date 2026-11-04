import GlassWorkCore
import SwiftUI

/// Picks the panel of a developer module. Panels take plain values, so tests can draw any state.
struct DeveloperPanel: View {
    let module: ModuleID
    let store: DeveloperStore

    var body: some View {
        switch module {
        case .aiUsage:
            AIUsagePanel(reading: store.aiUsage, refreshMinutes: store.options.aiRefreshMinutes) {
                store.refresh(.aiUsage)
            }
        case .git:
            GitPanel(
                reading: store.git,
                selected: store.options.gitRepository,
                manual: store.options.gitRepositories
            )
        case .devServers: DevServersPanel(reading: store.devServers)
        case .docker: DockerPanel(reading: store.docker)
        case .ping: PingPanel(log: store.ping, host: store.options.pingHost)
        case .vpn: VPNPanel(reading: store.vpn, since: store.vpnSince)
        case .wifi: WiFiPanel(reading: store.wifi, signal: store.wifiLastMinute)
        default: EmptyView()
        }
    }
}

extension PanelActions {
    /// Writes one `ModuleSettings.options` entry; nil removes it.
    func setOption(_ module: ModuleID, _ key: String, _ value: String?) {
        updateSettings { $0.update(module) { $0.options[key] = value } }
    }
}

/// Options for the module's page in Settings.
public struct DeveloperOptionsSection: View {
    private let module: ModuleID
    private let store: SettingsStore

    public init(module: ModuleID, store: SettingsStore) {
        self.module = module
        self.store = store
    }

    public var body: some View {
        switch module {
        case .aiUsage:
            Section(loc("Usage")) {
                Picker(loc("Refresh every"), selection: refreshMinutes) {
                    ForEach([1, 5, 15, 30, 60], id: \.self) { minutes in
                        Text(loc("\(minutes) min")).tag(minutes)
                    }
                }
            }
        case .ping:
            Section(loc("Host")) {
                PingHostField(host: option(DeveloperOptions.Key.host) ?? PingHost.fallback) { host in
                    setOption(DeveloperOptions.Key.host, host)
                }
            }
        default:
            EmptyView()
        }
    }

    private var refreshMinutes: Binding<Int> {
        Binding(
            get: { DeveloperOptions(settings: store.settings).aiRefreshMinutes },
            set: { setOption(DeveloperOptions.Key.refreshMinutes, String($0)) }
        )
    }

    private func option(_ key: String) -> String? {
        store.settings.module(module)?.options[key]
    }

    private func setOption(_ key: String, _ value: String?) {
        store.update { $0.update(module) { $0.options[key] = value } }
    }
}

/// Faint line that says what a read-only module will never do.
struct ReadOnlyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Icon, title and a line of explanation, for panels with nothing to list.
struct PanelMessage: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(tint)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
