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

struct DevServersPanel: View {
    let reading: DevServerReading?
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
                    actions.openURL(url)
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
            case .notRunning:
                PanelMessage(
                    symbol: "power",
                    title: loc("Docker is not running"),
                    detail: loc("Start it yourself; GlassWork never does.")
                )
            case .permissionDenied:
                PanelMessage(
                    symbol: "exclamationmark.triangle",
                    title: loc("Permission denied on docker.sock"),
                    tint: Palette.orange
                )
            case let .failed(message):
                PanelMessage(
                    symbol: "exclamationmark.triangle",
                    title: loc("Can't read containers"),
                    detail: message,
                    tint: Palette.orange
                )
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
