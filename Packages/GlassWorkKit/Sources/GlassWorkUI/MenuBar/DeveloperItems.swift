import GlassWorkCore
import SwiftUI

/// Menu bar content of the developer modules.
extension ItemContent {
    static func developer(_ module: ModuleID, _ store: DeveloperStore) -> ItemContent {
        switch module {
        case .ping: ping(store.ping)
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
}
