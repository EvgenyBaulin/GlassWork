import GlassWorkCore
import SwiftUI

/// Menu bar content of the developer modules.
extension ItemContent {
    static func developer(_ module: ModuleID, _ store: DeveloperStore) -> ItemContent {
        switch module {
        case .aiUsage: aiUsage(store.aiUsage)
        case .git: git(store.git, selected: store.options.gitRepository)
        case .devServers: devServers(store.devServers)
        case .docker: docker(store.docker)
        case .ping: ping(store.ping)
        case .vpn: vpn(store.vpn)
        case .wifi: wifi(store.wifi, signal: store.wifiSignal.points.map(\.value))
        default: ItemContent(figure: "—", template: "—")
        }
    }

    static func git(_ reading: GitReading?, selected: String?) -> ItemContent {
        let template = "feature/ab…cd ±99 ↑9 ↓9"
        guard let repository = reading?.selected(path: selected), let status = repository.status else {
            var item = ItemContent(figure: "—", template: template)
            item.isFaint = true
            return item
        }
        var item = ItemContent(figure: gitFigure(status), template: template)
        item.glyph = .dots(filled: status.changed + status.conflicted, faint: 0)
        item.symbol = status.conflicted > 0 ? "exclamationmark.triangle" : nil
        item.detail = repository.name
        return item
    }

    private static func gitFigure(_ status: GitStatus) -> String {
        var parts = [DeveloperText.middleTruncated(status.head, to: 13)]
        if status.isClean, status.ahead == 0, status.behind == 0 {
            parts.append("✓")
        }
        if status.changed > 0 {
            parts.append("±\(status.changed)")
        }
        if status.ahead > 0 {
            parts.append("↑\(status.ahead)")
        }
        if status.behind > 0 {
            parts.append("↓\(status.behind)")
        }
        return parts.joined(separator: " ")
    }

    static func devServers(_ reading: DevServerReading?) -> ItemContent {
        guard case let .servers(servers) = reading else {
            var item = ItemContent(figure: "—", template: "99")
            item.isFaint = true
            return item
        }
        var item = ItemContent(figure: "\(servers.count)", template: "99")
        item.glyph = .dots(filled: servers.count, faint: 0)
        item.detail = servers.prefix(5).map { ":\($0.port) \($0.process)" }.joined(separator: " · ")
        return item
    }

    static func docker(_ reading: DockerReading?) -> ItemContent {
        guard case let .containers(containers, _) = reading else {
            var item = ItemContent(figure: "—", template: "99")
            item.isFaint = true
            item.detail = reading == .notRunning ? loc("Docker is not running") : nil
            return item
        }
        let running = containers.count(where: \.isRunning)
        var item = ItemContent(figure: "\(running)", template: "99")
        item.glyph = .dots(filled: running, faint: containers.count - running)
        return item
    }

    static func ping(_ log: PingLog) -> ItemContent {
        var item = ItemContent(
            figure: pingFigure(log),
            alert: log.isDown ? Palette.red : nil,
            template: "999 ms"
        )
        item.values = log.replies
        item.isFaint = log.isOffline
        if let stats = log.stats {
            let low = DeveloperText.milliseconds(stats.minimum)
            let high = DeveloperText.milliseconds(stats.maximum)
            item.detail = "\(loc("min")) \(low) · \(loc("max")) \(high)"
        }
        return item
    }

    static func vpn(_ reading: VPNReading?) -> ItemContent {
        let isConnected = reading?.isConnected == true
        var item = ItemContent(
            figure: isConnected ? loc("On") : loc("Off"),
            alert: isConnected ? Palette.green : nil,
            template: "Off"
        )
        item.symbol = isConnected ? "shield.fill" : "shield"
        item.glyph = .symbol
        item.isFaint = reading?.isConnecting == true || reading?.isConfigured != true
        item.detail = reading?.connectedService?.name
        return item
    }

    static func wifi(_ reading: WiFiReading?, signal: [Double]) -> ItemContent {
        var item = ItemContent(
            figure: reading?.link.map { DeveloperText.decibels($0.rssi) } ?? "—",
            domain: WiFiSignal.domain,
            template: "−100 dBm"
        )
        item.values = signal
        switch reading {
        case let .connected(link):
            item.symbolLevel = Double(link.bars) / 3
        case .off:
            item.symbol = "wifi.slash"
            item.figure = loc("Off")
        default:
            item.symbolLevel = 0
            item.isFaint = true
        }
        return item
    }

    private static func pingFigure(_ log: PingLog) -> String {
        if log.isDown {
            return loc("Down")
        }
        return log.latest?.milliseconds.map(DeveloperText.milliseconds) ?? "—"
    }
}

/// Text shared by developer items and panels.
enum DeveloperText {
    static func milliseconds(_ value: Double) -> String {
        loc("\(Int(value.rounded())) ms")
    }

    /// `25 minutes ago`, measured from `now` so a panel and its tests agree.
    static func relative(_ date: Date, to now: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: now)
    }

    /// `feature/ab…cd`: the end of a branch name is usually what tells branches apart.
    static func middleTruncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let tail = limit / 3
        return "\(text.prefix(limit - tail - 1))…\(text.suffix(tail))"
    }

    /// With a true minus sign, as in `−58 dBm`.
    static func decibels(_ value: Int) -> String {
        loc("\(value < 0 ? "−" : "")\(abs(value)) dBm")
    }
}
