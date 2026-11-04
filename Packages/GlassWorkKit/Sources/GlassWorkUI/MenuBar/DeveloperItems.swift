import GlassWorkCore
import SwiftUI

/// Menu bar content of the developer modules.
extension ItemContent {
    static func developer(_ module: ModuleID, _ store: DeveloperStore) -> ItemContent {
        switch module {
        case .ping: ping(store.ping)
        case .vpn: vpn(store.vpn)
        case .wifi: wifi(store.wifi, signal: store.wifiSignal.points.map(\.value))
        default: ItemContent(figure: "—", template: "—")
        }
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

    /// With a true minus sign, as in `−58 dBm`.
    static func decibels(_ value: Int) -> String {
        loc("\(value < 0 ? "−" : "")\(abs(value)) dBm")
    }
}
