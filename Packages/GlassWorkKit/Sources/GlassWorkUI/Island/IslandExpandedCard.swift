import GlassWorkCore
import SwiftUI

struct IslandExpandedCard: View {
    let presentation: IslandPresentation
    let actions: IslandActions
    private var event: IslandEvent {
        presentation.event
    }

    private var now: Date {
        presentation.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case let .nowPlaying(session) = event.detail {
                IslandNowPlaying(presentation: presentation, session: session, actions: actions)
            } else if case let .levels(levels, _) = event.detail {
                // Both rows carry their own titles, as in the design.
                levelsContent(levels)
            } else {
                header
                content
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 30)
                .background(iconTint, in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if !presentation.subtitle.isEmpty {
                    Text(presentation.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if event.kind != .devServers {
                Text(presentation.value)
                    .font(.system(size: event.kind == .inProgress ? 19 : 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(presentation.tint)
                    .fixedSize()
            }
        }
    }

    private var iconTint: Color {
        if case .keepAwake = event.detail {
            return Color(red: 0.55, green: 0.37, blue: 0.25)
        }
        return presentation.tint
    }

    @ViewBuilder
    private var content: some View {
        switch event.detail {
        case let .meeting(meeting): meetingContent(meeting)
        case let .inProgress(meeting): inProgressContent(meeting)
        case let .timers(timers): timersContent(timers)
        case let .copied(entry): IslandClipboardPreview(
                entry: entry, data: event.context.clipboardPreview,
                imageURL: event.context.clipboardImageURL, actions: actions
            )
        case let .charging(battery): chargingContent(battery)
        case let .systemAlert(alert): systemContent(alert)
        case let .network(detail): networkContent(detail)
        case let .devServers(detail): developerContent(detail)
        case let .build(reading): buildContent(reading)
        case let .keepAwake(end): keepAwakeContent(end)
        case let .downloads(files): downloadsContent(files)
        case let .headphones(_, batteries): headphonesContent(batteries)
        case .nowPlaying, .weather, .levels, .focus: EmptyView()
        }
    }

    /// Each bud and the case, as the system reports them.
    private func headphonesContent(_ batteries: [DeviceBattery]) -> some View {
        VStack(spacing: 10) {
            ForEach(batteries) { battery in
                VStack(spacing: 5) {
                    HStack {
                        Text(battery.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text(Format.percent(battery.charge)).font(.system(size: 11, design: .monospaced))
                    }
                    ThinBar(value: battery.charge, tint: battery.charge < 0.2 ? Palette.red : Palette.green)
                }
            }
        }
    }

    /// Both levels, as in the design, each with its bar; the bars move the level when the host can set it.
    private func levelsContent(_ levels: SystemLevels) -> some View {
        VStack(spacing: 14) {
            if let volume = levels.volume {
                IslandLevelRow(
                    symbol: levels.isSilent ? "speaker.slash.fill" : "music.note",
                    title: loc("Volume"),
                    subtitle: levels.outputName ?? "",
                    value: levels.isMuted ? 0 : volume,
                    tint: Palette.pink,
                    set: actions.setVolume
                )
            }
            if let brightness = levels.brightness {
                IslandLevelRow(
                    symbol: "sun.max.fill",
                    title: loc("Brightness"),
                    subtitle: loc("Built-in display"),
                    value: brightness,
                    tint: Palette.yellow,
                    set: actions.setBrightness
                )
            }
        }
    }

    private func downloadsContent(_ files: [DockFile]) -> some View {
        VStack(spacing: 10) {
            ForEach(files.prefix(4)) { file in
                VStack(spacing: 5) {
                    HStack {
                        Text(file.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(file.isDownloading ? file.progress.map { Format.percent($0) } ?? "…" : loc("done"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ThinBar(
                        value: file.isDownloading ? file.progress ?? 0 : 1,
                        tint: file.isDownloading ? Palette.blue : Palette.green
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func meetingContent(_ meeting: AgendaEvent) -> some View {
        if meeting.callURL != nil {
            IslandRow(
                symbol: "video",
                title: loc("Join from here"),
                subtitle: loc("Opens the call link from the event"),
                tint: Palette.green
            )
        }
        HStack(spacing: 8) {
            if let url = meeting.callURL {
                IslandCapsule(title: loc("Join"), tint: Palette.green) { actions.joinMeeting(url) }
            }
            IslandCapsule(title: loc("Snooze 5 min"), action: actions.snooze)
            if let runningLate = actions.runningLate {
                IslandCapsule(title: loc("Running late…"), action: runningLate)
            }
        }
    }

    private func inProgressContent(_ meeting: AgendaEvent) -> some View {
        VStack(spacing: 10) {
            ThinBar(value: meeting.progress(at: now), tint: Palette.blue)
            HStack {
                Text(loc("started \(presentation.minutes(now.timeIntervalSince(meeting.start))) ago"))
                Spacer()
                Text(loc("ends \(presentation.clock(meeting.end))"))
            }
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            if let next = event.context.nextEvent {
                IslandRow(
                    symbol: "calendar",
                    title: loc("Next · \(next.title)"),
                    subtitle: presentation.nextDate(next.start),
                    tint: Palette.purple
                )
            }
        }
    }

    private func timersContent(_ timers: [CountdownTimer]) -> some View {
        VStack(spacing: 12) {
            let soonest = presentation.soonest(timers)?.id
            ForEach(timers) { timer in
                let finished = timer.isFinished(at: now)
                IslandRow(
                    symbol: finished ? "exclamationmark.triangle" : "timer", title: timer.title,
                    subtitle: finished ? loc("Timer’s up") : presentation.minutes(timer.duration),
                    value: presentation.timerValue(timer),
                    tint: finished ? Palette.red : (timer.id == soonest ? Palette.orange : Palette.gray),
                    valueTint: finished ? Palette.red : (timer.id == soonest ? Palette.orange : .white)
                )
            }
            HStack(spacing: 8) {
                IslandCapsule(title: loc("+1 min"), action: actions.addMinute)
                IslandCapsule(title: loc("Stop"), tint: Palette.red, action: actions.stopTimers)
                IslandCapsule(title: loc("Add timer"), action: actions.addTimer)
            }
        }
    }

    private func chargingContent(_ battery: BatterySample) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(loc("Battery"))
                Spacer()
                Text(Format.percent(battery.charge)).monospacedDigit()
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            ThinBar(value: battery.charge, tint: Palette.green)
        }
    }

    private func systemContent(_ alert: IslandSystemAlert) -> some View {
        VStack(spacing: 12) {
            if let process = alert.topProcess {
                IslandRow(
                    symbol: "keyboard",
                    title: process.name,
                    subtitle: loc("\(Format.corePercent(process.cpu)) CPU"),
                    value: loc("Top"),
                    tint: Palette.orange,
                    action: actions.showTop
                )
            }
            if let volume = alert.lowSpaceVolume {
                IslandRow(
                    symbol: "internaldrive",
                    title: loc("Disk almost full"),
                    subtitle: loc("\(Format.size(Double(volume.free))) free on \(volume.name)"),
                    value: Format.size(Double(volume.free)),
                    tint: Palette.red
                )
            }
            HStack(spacing: 8) {
                if event.context.fanRPM != nil {
                    IslandCapsule(title: loc("Fans to Max"), tint: Palette.orange, action: actions.fansToMax)
                }
                IslandCapsule(title: loc("Open Activity Monitor"), action: actions.openActivityMonitor)
            }
        }
    }

    private func networkContent(_ detail: IslandNetworkDetail) -> some View {
        VStack(spacing: 12) {
            if let vpn = event.context.vpn, !vpn.isConnected, vpn.isConfigured {
                IslandRow(
                    symbol: "lock",
                    title: loc("VPN disconnected"),
                    subtitle: loc("\(vpn.services.first?.name ?? loc("VPN")) · traffic not protected"),
                    value: loc("off"),
                    tint: Palette.orange
                )
            }
            if let ping = event.context.ping {
                IslandRow(
                    symbol: "globe",
                    title: pingTitle(detail),
                    subtitle: pingSubtitle(ping), value: presentation.pingValue(ping),
                    tint: pingTint(ping)
                )
            }
            HStack(spacing: 8) {
                if event.context.vpn?.isConfigured == true, let reconnect = actions.reconnectVPN {
                    IslandCapsule(title: loc("Reconnect VPN"), tint: Palette.blue, action: reconnect)
                }
                IslandCapsule(title: loc("Network settings"), action: actions.openNetworkSettings)
            }
        }
    }

    private func pingTitle(_ detail: IslandNetworkDetail) -> String {
        if case .pingRecovered = detail {
            return loc("Ping back to normal")
        }
        if let previous = event.context.previousPing, let current = event.context.ping,
           !isHealthyPing(previous), isHealthyPing(current)
        {
            return loc("Ping back to normal")
        }
        return loc("Ping")
    }

    private func isHealthyPing(_ ping: PingOutcome) -> Bool {
        if case let .reply(milliseconds) = ping {
            return milliseconds <= 300
        }
        return false
    }

    private func pingSubtitle(_ ping: PingOutcome) -> String {
        var values = [event.context.pingHost, presentation.pingValue(ping)].compactMap(\.self)
        if let previous = event.context.previousPing {
            values.append(loc("was \(presentation.pingValue(previous))"))
        }
        return values.joined(separator: " · ")
    }

    private func pingTint(_ ping: PingOutcome) -> Color {
        if case let .reply(milliseconds) = ping {
            return milliseconds <= 300 ? Palette.green : Palette.orange
        }
        return Palette.red
    }

    private func developerContent(_ detail: IslandDeveloperDetail) -> some View {
        VStack(spacing: 12) {
            ForEach(event.context.servers) { server in
                IslandRow(
                    symbol: "play.fill",
                    title: loc("\(server.tool ?? server.process) server is up"),
                    subtitle: server.address,
                    value: ":\(server.port)",
                    tint: Palette.green
                )
            }
            HStack(spacing: 8) {
                if case let .containerExited(container) = detail {
                    if let restart = actions.restartContainer {
                        IslandCapsule(title: loc("Restart \(container.name)"), tint: Palette.red) {
                            restart(container.name)
                        }
                    }
                    if let logs = actions.containerLogs {
                        IslandCapsule(title: loc("Logs")) { logs(container.name) }
                    }
                }
                if let server = openableServer(detail), let url = server.url {
                    IslandCapsule(title: loc("Open :\(String(server.port))")) { actions.openURL(url) }
                }
            }
        }
    }

    private func openableServer(_ detail: IslandDeveloperDetail) -> DevServer? {
        if case let .serverAppeared(server) = detail, server.url != nil {
            return server
        }
        return event.context.servers.first { $0.url != nil }
    }

    /// Counts of what the build found, and a way to the project that produced them.
    private func buildContent(_ reading: BuildReading) -> some View {
        VStack(spacing: 12) {
            if case let .finished(result) = reading {
                IslandRow(
                    symbol: "xmark.octagon", title: loc("Errors"), subtitle: "",
                    value: String(result.errors), tint: result.errors > 0 ? Palette.red : Palette.gray
                )
                IslandRow(
                    symbol: "exclamationmark.triangle", title: loc("Warnings"), subtitle: "",
                    value: String(result.warnings), tint: result.warnings > 0 ? Palette.orange : Palette.gray
                )
            }
            HStack(spacing: 8) {
                IslandCapsule(title: loc("Open Xcode"), action: actions.openXcode)
            }
        }
    }

    private func keepAwakeContent(_ end: Date) -> some View {
        VStack(spacing: 12) {
            ThinBar(
                value: now.timeIntervalSince(event.since) / max(end.timeIntervalSince(event.since), 1),
                tint: Palette.green
            )
            HStack(spacing: 8) {
                IslandCapsule(title: loc("+15 m")) { actions.extendKeepAwake(900) }
                IslandCapsule(title: loc("+1 h")) { actions.extendKeepAwake(3600) }
                IslandCapsule(title: loc("Stop"), tint: Palette.red, action: actions.stopKeepAwake)
            }
        }
    }
}
