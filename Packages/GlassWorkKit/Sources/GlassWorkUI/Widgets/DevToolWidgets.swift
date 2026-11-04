import GlassWorkCore
import SwiftUI
import WidgetKit

/// What is listening on this Mac. Only reads: no process is ever stopped.
struct DevServersWidget: View {
    let context: TimeContext

    private var servers: [DevServer] {
        context.snapshot.devServers?.servers ?? []
    }

    private var web: [DevServer] {
        servers.filter { $0.kind == .web }
    }

    private var services: [DevServer] {
        servers.filter { $0.kind == .service }
    }

    private var header: some View {
        WidgetHeader(title: loc("Dev Servers"), symbol: "server.rack", tint: Palette.green)
    }

    var body: some View {
        if context.snapshot.devServers == nil {
            WidgetChecking(symbol: "server.rack", tint: Palette.green)
        } else if context.snapshot.devServers == .failed {
            WidgetEmptyState(symbol: "server.rack", title: loc("Can't read servers"), tint: Palette.green)
        } else if servers.isEmpty {
            WidgetEmptyState(
                symbol: "server.rack",
                title: loc("Nothing running"),
                detail: context.size == .small ? nil : loc("Start a dev server and it appears here."),
                tint: Palette.green
            )
        } else {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 4) {
                    header
                    count(size: 30)
                    dots
                    Spacer(minLength: 0)
                    if let first = servers.first {
                        HStack(spacing: 6) {
                            port(first)
                            Text(first.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                    }
                }
            case .medium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        header
                        count(size: 34)
                        Spacer(minLength: 0)
                        dots
                    }
                    .frame(width: 112)
                    VStack(spacing: 5) {
                        ForEach(servers.prefix(3)) { card($0, showsUptime: false) }
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        header
                        Spacer()
                        dots
                    }
                    count(size: 30)
                    ForEach(servers.prefix(5)) { card($0, showsUptime: true) }
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        header
                        ForEach(servers.prefix(6)) { card($0, showsUptime: true) }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 400)
                    Divider()
                    details(servers[0])
                }
            }
        }
    }

    private func count(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(verbatim: "\(web.count)").font(.widgetFigure(size))
            VStack(alignment: .leading, spacing: 0) {
                Text(loc("running")).font(.system(size: 12)).foregroundStyle(.secondary)
                if !services.isEmpty {
                    Text(verbatim: "+ \(loc("\(services.count) services"))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(servers.prefix(10)) { server in
                Circle().fill(tint(server)).frame(width: 7, height: 7).widgetAccentable()
            }
        }
    }

    private func tint(_ server: DevServer) -> Color {
        server.kind == .web ? Palette.green : Palette.cyan
    }

    @ViewBuilder
    private func card(_ server: DevServer, showsUptime: Bool) -> some View {
        if let url = server.url {
            Link(destination: url) { cardContent(server, showsUptime: showsUptime) }.buttonStyle(.plain)
        } else {
            cardContent(server, showsUptime: showsUptime)
        }
    }

    private func cardContent(_ server: DevServer, showsUptime: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: server.kind == .web ? "terminal" : "cylinder.split.1x2")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(server.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(subtitle(server, showsUptime: showsUptime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            port(server)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private func subtitle(_ server: DevServer, showsUptime: Bool) -> String {
        var parts = [server.process]
        if let tool = server.tool {
            parts.append(tool)
        }
        if showsUptime, let uptime = server.uptime {
            parts.append(loc("up \(CompactDuration.format(uptime))"))
        }
        return parts.joined(separator: " · ")
    }

    private func port(_ server: DevServer) -> some View {
        Text(verbatim: ":\(server.port)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint(server))
            .lineLimit(1)
            .fixedSize()
            .widgetAccentable()
    }

    private func details(_ server: DevServer) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(server.project).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text(server.copyText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.blue)
                .lineLimit(1)
            Divider()
            WidgetFact(title: loc("Process"), value: "\(server.process) · \(server.pid)")
            if let tool = server.tool {
                WidgetFact(title: loc("Command"), value: tool)
            }
            if let uptime = server.uptime {
                WidgetFact(title: loc("Running for"), value: CompactDuration.format(uptime))
            }
            Spacer(minLength: 0)
            if let url = server.url {
                Link(destination: url) {
                    Text(loc("Open in browser"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .widgetSolid(Palette.blue, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            Text(loc("GlassWork never stops or restarts processes."))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }
}

/// Docker containers through the current context. Only reads: nothing is started or removed.
struct ContainersWidget: View {
    let context: TimeContext

    private var containers: [DockerContainer] {
        context.snapshot.docker?.containers ?? []
    }

    private var running: Int {
        containers.count(where: \.isRunning)
    }

    private var dockerContext: String? {
        if case let .containers(_, name) = context.snapshot.docker {
            return name
        }
        return nil
    }

    private var header: some View {
        WidgetHeader(title: loc("Containers"), symbol: "shippingbox", tint: Palette.blue)
    }

    var body: some View {
        if context.snapshot.docker == nil {
            WidgetChecking(symbol: "shippingbox", tint: Palette.blue)
        } else if let problem {
            WidgetEmptyState(symbol: "shippingbox", title: problem, tint: Palette.blue)
        } else {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 4) {
                    header
                    count(size: 30)
                    squares
                    Spacer(minLength: 0)
                    if let first = containers.first {
                        Text(first.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if let port = firstPort(first) {
                            Text(verbatim: port).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Palette.blue)
                        }
                    }
                }
            case .medium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        header
                        count(size: 34)
                        Spacer(minLength: 0)
                        squares
                    }
                    .frame(width: 112)
                    VStack(spacing: 7) {
                        ForEach(containers.prefix(3)) { row($0) }
                        Spacer(minLength: 0)
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 7) {
                    title
                    HStack(alignment: .bottom) {
                        count(size: 30)
                        Spacer()
                        squares
                    }
                    Divider()
                    ForEach(containers.prefix(7)) { row($0) }
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        title
                        ForEach(containers.prefix(8)) { row($0) }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 400)
                    Divider()
                    summary
                }
            }
        }
    }

    /// What stands in for the list when Docker gave no answer. Nil when there is a list, even an empty one.
    private var problem: String? {
        switch context.snapshot.docker {
        case .notInstalled: loc("Docker is not installed")
        case .notRunning: loc("Docker is not running")
        case .permissionDenied: loc("No access to Docker")
        case .failed: loc("Can't read Docker")
        case let .containers(list, _): list.isEmpty ? loc("No containers") : nil
        case nil: nil
        }
    }

    private var title: some View {
        HStack {
            header
            Spacer()
            if let name = dockerContext {
                Text(verbatim: name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.blue.opacity(0.15), in: .capsule)
            }
        }
    }

    private func count(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(verbatim: "\(running)").font(.widgetFigure(size))
            Text(loc("of \(containers.count) running"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var squares: some View {
        HStack(spacing: 4) {
            ForEach(containers.prefix(10)) { container in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(container.isRunning ? AnyShapeStyle(Palette.green) : AnyShapeStyle(.quaternary))
                    .frame(width: 10, height: 10)
                    .widgetAccentable(container.isRunning)
            }
        }
    }

    private func row(_ container: DockerContainer) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(container.isRunning ? AnyShapeStyle(Palette.green) : AnyShapeStyle(.quaternary))
                .frame(width: 8, height: 8)
                .widgetAccentable(container.isRunning)
            VStack(alignment: .leading, spacing: 0) {
                Text(container.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(verbatim: "\(container.image) · \(container.status)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let port = firstPort(container) {
                Text(verbatim: container.ports.count > 1 ? "\(port) +\(container.ports.count - 1)" : port)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.blue)
                    .lineLimit(1)
                    .fixedSize()
                    .widgetAccentable()
            }
        }
    }

    /// Ports read `5432→5432`; the side on this Mac is the one to show.
    private func firstPort(_ container: DockerContainer) -> String? {
        container.ports.first.map { ":\($0.split(separator: "→").first ?? "")" }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            WidgetSection(title: loc("Summary"))
            WidgetFact(title: loc("Running"), value: "\(running)")
            WidgetFact(title: loc("Stopped"), value: "\(containers.count - running)")
            WidgetFact(title: loc("Published ports"), value: "\(containers.map(\.ports.count).reduce(0, +))")
            if let name = dockerContext {
                WidgetFact(title: loc("Context"), value: name)
            }
            Spacer(minLength: 0)
            Text(loc("Read-only: never starts, stops or removes containers."))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }
}
