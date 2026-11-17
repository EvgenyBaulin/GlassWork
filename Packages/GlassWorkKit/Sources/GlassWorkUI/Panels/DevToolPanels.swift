import AppKit
import GlassWorkCore
import SwiftUI

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Small square button used for row actions.
struct RowIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 6))
                .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A browser the user can pick to open dev servers in.
struct BrowserApp: Identifiable, Equatable {
    let bundleID: String
    let name: String

    var id: String {
        bundleID
    }

    /// Apps that open an http link, found the way the system's own "Open With" finds them.
    @MainActor
    static func installed() -> [BrowserApp] {
        guard let sample = URL(string: "https://localhost") else { return [] }
        var seen = Set<String>()
        let found = NSWorkspace.shared.urlsForApplications(toOpen: sample).compactMap { url -> BrowserApp? in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, seen.insert(bundleID).inserted else { return nil }
            return BrowserApp(
                bundleID: bundleID,
                name: FileManager.default.displayName(atPath: url.path)
                    .replacing(".app", with: "")
            )
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Opens `url` in the chosen app, or in the default browser when none is chosen or it is gone.
    @MainActor
    static func open(_ url: URL, in bundleID: String?, fallback: (URL) -> Void) {
        guard let bundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            fallback(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// "Default browser" or one of the installed browsers.
struct BrowserPicker: View {
    let selection: String?
    let onChange: (String?) -> Void

    var body: some View {
        let browsers = BrowserApp.installed()
        Picker(loc("Open in"), selection: Binding(get: { selection }, set: onChange)) {
            Text(loc("Default browser")).tag(String?.none)
            ForEach(browsers) { browser in
                Text(browser.name).tag(String?.some(browser.bundleID))
            }
            if let selection, !browsers.contains(where: { $0.bundleID == selection }) {
                Text(selection).tag(String?.some(selection))
            }
        }
    }
}

struct DevServersPanel: View {
    let reading: DevServerReading?
    var opener: String?
    @Environment(\.panelActions) private var actions
    @State private var hovered: String?

    private var servers: [DevServer] {
        if case let .servers(servers) = reading {
            return servers
        }
        return []
    }

    var body: some View {
        PanelFrame(
            module: .devServers,
            subtitle: subtitle,
            footerTitle: servers.isEmpty ? nil : loc("Copy all URLs"),
            footerAction: { Clipboard.copy(servers.map(\.copyText).joined(separator: "\n")) }
        ) {
            switch reading {
            case nil:
                PanelMessage(symbol: "server.rack", title: loc("Looking for servers…"))
            case .failed:
                PanelMessage(
                    symbol: "exclamationmark.triangle",
                    title: loc("Can't list servers"),
                    detail: loc("lsof did not answer."),
                    tint: Palette.orange
                )
            case .servers where servers.isEmpty:
                PanelMessage(
                    symbol: "server.rack",
                    title: loc("No local servers"),
                    detail: loc("Servers you start show up here.")
                )
            case .servers:
                ForEach(servers.prefix(12)) { server in
                    row(server)
                }
                if servers.count > 12 {
                    Text(loc("and \(servers.count - 12) more")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                BrowserPicker(selection: opener) { actions.setOption(.devServers, DeveloperOptions.Key.openIn, $0) }
                    .controlSize(.small)
                ReadOnlyNote(
                    text: loc("Read-only: GlassWork never stops or kills a server. Quit it where it runs (Terminal).")
                )
            }
        }
    }

    private var subtitle: String {
        let services = servers.count { $0.kind == .service }
        let web = servers.count - services
        let parts = [
            web == 0 ? nil : web == 1 ? loc("1 server") : loc("\(web) servers"),
            services == 0 ? nil : services == 1 ? loc("1 service") : loc("\(services) services"),
        ]
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    private func row(_ server: DevServer) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: ":\(server.port)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.green)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(server.tool.map { "\(server.process) · \($0)" } ?? server.process)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if server.kind == .service {
                        Text(loc("service"))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(detail(server)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            RowIconButton(symbol: "doc.on.doc", help: loc("Copy \(server.copyText)")) {
                Clipboard.copy(server.copyText)
            }
            if let url = server.url {
                RowIconButton(symbol: "arrow.up.right.square", help: loc("Open in browser")) {
                    BrowserApp.open(url, in: opener, fallback: actions.openURL)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(.white.opacity(hovered == server.id ? 0.07 : 0), in: .rect(cornerRadius: 8))
        .onHover { hovered = $0 ? server.id : nil }
    }

    private func detail(_ server: DevServer) -> String {
        let uptime = server.uptime.map { loc("up \(CompactDuration.format($0))") }
        return [server.project, uptime].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct DockerPanel: View {
    let reading: DockerReading?
    var contexts: [DockerContext] = []
    var onRetry: () -> Void = {}
    var onUseContext: (String) -> Void = { _ in }
    @Environment(\.panelActions) private var actions
    @State private var selected: String?

    private var containers: [DockerContainer] {
        reading?.containers ?? []
    }

    /// Click a row to pick which ID the footer copies.
    private var target: DockerContainer? {
        containers.first { $0.id == selected } ?? containers.first
    }

    var body: some View {
        PanelFrame(
            module: .docker,
            subtitle: subtitle,
            footerTitle: target == nil ? nil : loc("Copy Container ID"),
            footerAction: { target.map { Clipboard.copy($0.id) } }
        ) {
            switch reading {
            case nil:
                PanelMessage(symbol: "shippingbox", title: loc("Looking for containers…"))
            case .notInstalled:
                PanelMessage(
                    symbol: "shippingbox",
                    title: loc("docker not found"),
                    detail: loc("Install Docker Desktop, OrbStack or Colima.")
                )
                recovery(choosesBinary: true)
            case .notRunning:
                PanelMessage(
                    symbol: "power",
                    title: loc("Docker is not running"),
                    detail: loc("Start it yourself; GlassWork never does.")
                )
                recovery(choosesBinary: false)
            case .permissionDenied:
                PanelMessage(
                    symbol: "exclamationmark.triangle",
                    title: loc("Permission denied on docker.sock"),
                    tint: Palette.orange
                )
                recovery(choosesBinary: false)
            case let .failed(message):
                PanelMessage(
                    symbol: "exclamationmark.triangle",
                    title: loc("Can't read containers"),
                    detail: message,
                    tint: Palette.orange
                )
                recovery(choosesBinary: true)
            case .containers where containers.isEmpty:
                PanelMessage(symbol: "shippingbox", title: loc("No containers"))
            case .containers:
                list
            }
        }
    }

    private var subtitle: String {
        if case let .containers(_, context?) = reading {
            return loc("context: \(context)")
        }
        return ""
    }

    /// What can be done about an unreadable Docker: try again, pick another context or another binary.
    private func recovery(choosesBinary: Bool) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button(loc("Retry"), action: onRetry)
                if choosesBinary {
                    Button(loc("Choose docker…")) {
                        DockerBinaryPicker.choose { path in
                            actions.setOption(.docker, DeveloperOptions.Key.dockerPath, path)
                        }
                    }
                }
            }
            contextMenu
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }

    /// Only when there is something to choose from.
    @ViewBuilder
    private var contextMenu: some View {
        if contexts.count > 1 {
            Menu(loc("Context")) {
                ForEach(contexts) { context in
                    Button {
                        onUseContext(context.name)
                    } label: {
                        Text(context.isCurrent ? "✓ \(context.name)" : context.name)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var list: some View {
        let running = containers.count(where: \.isRunning)
        Text(loc("\(running) running · \(containers.count - running) stopped"))
            .font(.system(size: 13, weight: .semibold))
        ForEach(containers.prefix(12)) { container in
            row(container)
        }
        if containers.count > 12 {
            Text(loc("and \(containers.count - 12) more")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        contextMenu
        ReadOnlyNote(text: loc("Read-only: never starts, stops or removes containers."))
    }

    private func row(_ container: DockerContainer) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(container.isRunning ? Palette.green : Palette.gray)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(container.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(container.image) · \(container.status)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                ForEach(container.ports.prefix(2), id: \.self) { port in
                    Text(port).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.blue)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(.white.opacity(selected == container.id ? 0.07 : 0), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onTapGesture { selected = container.id }
    }
}

/// Asks for the docker command line tool when it is not in the usual folders.
enum DockerBinaryPicker {
    @MainActor
    static func choose(_ onChoose: @escaping @MainActor (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = loc("Choose the docker command line tool")
        NSApp.activate()
        panel.begin { response in
            if response == .OK, let url = panel.url {
                MainActor.assumeIsolated { onChoose(url.path) }
            }
        }
    }
}
