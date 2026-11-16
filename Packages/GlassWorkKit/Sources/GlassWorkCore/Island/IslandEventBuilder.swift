import Foundation

public enum IslandEventBuilder {
    public static let transientDuration: TimeInterval = 4

    public static func events(current: IslandInput, previous: IslandInput?, now: Date) -> [IslandEvent] {
        var result = ongoing(current, now: now)
        guard let previous else { return enriched(result, input: current, now: now) }
        result += network(current, previous: previous, now: now)
        result += developer(current, previous: previous, now: now)
        if previous.battery?.isOnAC == false, let battery = current.battery, battery.isOnAC {
            result.append(transient(id: "charging", kind: .charging, detail: .charging(battery), now: now))
        }
        if let entry = current.clipboardEntry, entry.id != previous.clipboardEntry?.id {
            result.append(transient(id: "copied", kind: .copied, detail: .copied(entry), now: now))
        }
        return enriched(result, input: current, now: now)
    }

    private static func enriched(_ events: [IslandEvent], input: IslandInput, now: Date) -> [IslandEvent] {
        let context = IslandContext(input: input, now: now)
        return events.map { event in
            var event = event
            event.context = context
            return event
        }
    }

    private static func ongoing(_ input: IslandInput, now: Date) -> [IslandEvent] {
        var result = calendar(input.calendarEvents, now: now)
        if input.timers.contains(where: { !$0.isPaused && $0.endDate != nil }) {
            result.append(IslandEvent(id: "timers", kind: .timers, since: now, detail: .timers(input.timers)))
        }
        let temperature = input.sensors?.averageCPU
        let isHot = temperature.map { $0 >= Double(input.alerts.highTemperature) } ?? false
        let lowSpace = input.volumes.first { $0.path == "/" && $0.free < input.lowSpaceBytes }
        if isHot || lowSpace != nil {
            let detail = IslandSystemAlert(
                averageCPU: temperature, topProcess: input.processes.max { $0.cpu < $1.cpu },
                lowSpaceVolume: lowSpace
            )
            result.append(IslandEvent(id: "systemAlert", kind: .systemAlert, since: now, detail: .systemAlert(detail)))
        }
        if input.isKeepingAwake, let end = input.keepAwakeEnds, end > now {
            result.append(IslandEvent(id: "keepAwake", kind: .keepAwake, since: now, detail: .keepAwake(endsAt: end)))
        }
        if let session = input.nowPlaying, session.isPlaying {
            result.append(IslandEvent(id: "nowPlaying", kind: .nowPlaying, since: now, detail: .nowPlaying(session)))
        }
        return result
    }

    private static func calendar(_ events: [AgendaEvent], now: Date) -> [IslandEvent] {
        let usable = events.filter { !$0.isDeclined && !$0.isAllDay }
        var result: [IslandEvent] = []
        if let next = usable.filter({ $0.start > now && $0.start <= now.addingTimeInterval(300) })
            .min(by: { $0.start < $1.start })
        {
            result.append(IslandEvent(id: "meeting:\(next.id)", kind: .meeting, since: now, detail: .meeting(next)))
        }
        // Multi-day timed events become relevant only during their final day.
        if let running = usable.filter({
            $0.start <= now && now < $0.end && $0.end.timeIntervalSince(now) < 86400
        }).min(by: { $0.end < $1.end }) {
            result.append(IslandEvent(
                id: "inProgress:\(running.id)", kind: .inProgress, since: now, detail: .inProgress(running)
            ))
        }
        return result
    }

    private static func network(_ current: IslandInput, previous: IslandInput, now: Date) -> [IslandEvent] {
        var result: [IslandEvent] = []
        if previous.wifi?.link != nil, let wifi = current.wifi, wifi.link == nil {
            result.append(IslandEvent(id: "wifi", kind: .network, since: now, detail: .network(.wifiLost(wifi))))
        }
        if previous.vpn?.isConnected == true, let vpn = current.vpn, !vpn.isConnected {
            result.append(IslandEvent(id: "vpn", kind: .network, since: now, detail: .network(.vpnOff(vpn))))
        }
        if let old = previous.ping, let ping = current.ping, isBadPing(old), !isBadPing(ping) {
            result.append(transient(id: "ping", kind: .network, detail: .network(.pingRecovered(ping)), now: now))
        }
        return result
    }

    private static func isBadPing(_ outcome: PingOutcome) -> Bool {
        if case let .reply(milliseconds) = outcome {
            return milliseconds > 300
        }
        return true
    }

    private static func developer(_ current: IslandInput, previous: IslandInput, now: Date) -> [IslandEvent] {
        var result: [IslandEvent] = []
        if case let .containers(containers, _) = current.docker,
           case let .containers(old, _) = previous.docker
        {
            let running = Set(old.filter(\.isRunning).map(\.id))
            for container in containers where !container.isRunning
                && container.status.lowercased().hasPrefix("exited") && running.contains(container.id)
            {
                result.append(IslandEvent(
                    id: "container:\(container.id)", kind: .devServers, since: now,
                    detail: .devServers(.containerExited(container))
                ))
            }
        }
        if case let .servers(servers) = current.devServers, case let .servers(old) = previous.devServers {
            let known = Set(old.map(\.id))
            for server in servers where !known.contains(server.id) {
                result.append(transient(
                    id: "server:\(server.id)", kind: .devServers, detail: .devServers(.serverAppeared(server)), now: now
                ))
            }
        }
        return result
    }

    private static func transient(id: String, kind: IslandEventKind, detail: IslandDetail, now: Date) -> IslandEvent {
        IslandEvent(id: id, kind: kind, since: now, expires: now.addingTimeInterval(transientDuration), detail: detail)
    }
}
