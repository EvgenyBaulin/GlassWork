import GlassWorkCore
import SwiftUI

/// Menu bar content of the system modules, following each module's options.
extension ItemContent {
    static func percent(_ value: Double?, metric: Metric, style: NumberStyle) -> ItemContent {
        ItemContent(
            figure: value.map { Format.percent($0, style: style) } ?? "—",
            metric: metric,
            domain: 0 ... 1,
            template: style == .compact ? "100%" : "100.0%"
        )
    }

    static func overview(_ monitor: SystemMonitor, options: [String: String]) -> ItemContent {
        var parts: [String] = []
        if options.flag(ItemOption.showsCPU, default: true) {
            parts.append(Format.percent(monitor.cpu?.total ?? 0))
        }
        if options.flag(ItemOption.showsMemory, default: true) {
            parts.append(Format.percent(monitor.memory?.usedShare ?? 0))
        }
        if options.flag(ItemOption.showsDisk, default: false) {
            parts.append(Format.percent(1 - (monitor.volumes.first?.freeShare ?? 1)))
        }
        return ItemContent(
            figure: parts.isEmpty ? "—" : parts.joined(separator: " "),
            metric: .cpu,
            domain: 0 ... 1,
            template: Array(repeating: "100%", count: max(parts.count, 1)).joined(separator: " ")
        )
    }

    static func cpu(_ monitor: SystemMonitor, style: NumberStyle, options: [String: String]) -> ItemContent {
        var item = percent(monitor.cpu?.total, metric: .cpu, style: style)
        let limit = Double(options.number(ItemOption.highlightAbove, default: 80)) / 100
        if let total = monitor.cpu?.total, total >= limit {
            item.alert = Palette.orange
        }
        return item
    }

    static func memory(_ sample: MemorySample?, style: NumberStyle, options: [String: String]) -> ItemContent {
        var item = switch options.choice(ItemOption.memoryFigure, default: MemoryFigure.share) {
        case .share:
            percent(sample?.usedShare, metric: .memory, style: style)
        case .gigabytes:
            ItemContent(
                figure: sample.map { Format.bytes(Double($0.used), style: style) } ?? "—",
                metric: .memory,
                domain: 0 ... 1,
                template: style == .compact ? "999G" : "999.9 GB"
            )
        case .pressure:
            ItemContent(
                figure: sample.map { pressureTitle($0.pressure) } ?? "—",
                metric: .memory,
                domain: 0 ... 1,
                template: loc("Medium")
            )
        }
        if options.flag(ItemOption.colorsByPressure, default: true) {
            switch sample?.pressure {
            case .warning: item.alert = Palette.orange
            case .critical: item.alert = Palette.red
            default: break
            }
        }
        return item
    }

    private static func pressureTitle(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: loc("Low")
        case .warning: loc("Medium")
        case .critical: loc("High")
        }
    }

    static func disk(_ monitor: SystemMonitor, style: NumberStyle, options: [String: String]) -> ItemContent {
        let volume = monitor.volumes.first
        let free = volume.map { Format.bytes(Double($0.free), style: style) } ?? "—"
        let read = "↓ \(Format.rate(monitor.diskActivity?.read ?? 0, style: style))"
        let written = "↑ \(Format.rate(monitor.diskActivity?.write ?? 0, style: style))"
        let wide = style == .compact ? "↓ 999M/s" : "↓ 999.9 MB/s"
        let isLow = (volume?.freeShare ?? 1) < 0.1
        return switch options.choice(ItemOption.diskFigure, default: DiskFigure.free) {
        case .free:
            ItemContent(
                figure: free,
                metric: .diskRead,
                alert: isLow ? Palette.orange : nil,
                template: style == .compact ? "999G" : "999.9 GB"
            )
        case .activity:
            ItemContent(figure: read, secondLine: written, metric: .diskRead, template: wide)
        case .both:
            ItemContent(
                figure: "\(free) \(read)",
                secondLine: written,
                metric: .diskRead,
                alert: isLow ? Palette.orange : nil,
                template: "999.9 GB \(wide)"
            )
        }
    }

    static func network(_ sample: NetworkSample?, style: NumberStyle, options: [String: String]) -> ItemContent {
        let isBits = options.choice(ItemOption.rateUnit, default: RateUnit.bytes) == .bits
        let threshold = Double(options.number(ItemOption.hideBelow, default: 0))
        func text(_ value: Double) -> String {
            guard value >= threshold else { return "—" }
            return isBits ? Format.bitRate(value, style: style) : Format.rate(value, style: style)
        }
        let download = "↓ \(text(sample?.download ?? 0))"
        let upload = "↑ \(text(sample?.upload ?? 0))"
        let template = style == .compact ? "↓ 999M/s" : "↓ 999.9 Mbit/s"
        return switch options.choice(ItemOption.networkDirection, default: NetworkDirection.both) {
        case .both: ItemContent(figure: download, secondLine: upload, metric: .download, template: template)
        case .download: ItemContent(figure: download, metric: .download, template: template)
        case .upload: ItemContent(figure: upload, metric: .upload, template: template)
        }
    }

    static func battery(_ sample: BatterySample?, style: NumberStyle, options: [String: String]) -> ItemContent {
        let limit = Double(options.number(ItemOption.lowPercent, default: 10)) / 100
        let isLow = (sample?.charge ?? 1) <= limit && sample?.isCharging == false
        let showsTime = options.choice(ItemOption.batteryFigure, default: BatteryFigure.charge) == .timeLeft
        let figure = if showsTime {
            sample?.minutesRemaining.map { TimeInterval($0 * 60).hoursAndMinutes } ?? "—"
        } else {
            sample.map { Format.percent($0.charge, style: style) } ?? "—"
        }
        var item = ItemContent(figure: figure, alert: isLow ? Palette.red : nil, template: showsTime ? "88:88" : "100%")
        if options.flag(ItemOption.hidesWhenFull, default: false), let sample, sample.charge >= 1, sample.isOnAC {
            item.isHidden = true
        }
        return item
    }

    static func uptime(since boot: Date, now: Date = Date(), options: [String: String]) -> ItemContent {
        let interval = now.timeIntervalSince(boot)
        return switch options.choice(ItemOption.uptimeFormat, default: UptimeFormat.compact) {
        case .compact: ItemContent(figure: CompactDuration.format(interval), template: "99d 23h")
        case .days: ItemContent(figure: loc("\(UptimeFormat.wholeDays(interval)) days"), template: "999 days")
        case .hours: ItemContent(figure: UptimeFormat.hoursText(interval), template: "9999:59")
        }
    }

    static func deviceBatteries(_ devices: [DeviceBattery], options: [String: String]) -> ItemContent {
        let lowest = devices.min { $0.charge < $1.charge }
        let limit = Double(options.number(ItemOption.warnBelow, default: 20)) / 100
        return ItemContent(
            figure: lowest.map { Format.percent($0.charge) } ?? "—",
            alert: (lowest?.charge ?? 1) < limit ? Palette.red : nil,
            template: "100%"
        )
    }

    static func timers(_ remaining: TimeInterval?, options: [String: String]) -> ItemContent {
        guard options.flag(ItemOption.showsSeconds, default: true) else {
            let minutes = remaining.map { Int(($0 / 60).rounded(.up)) }
            return ItemContent(figure: minutes.map { loc("\($0) min") } ?? "—", template: "888 min")
        }
        return ItemContent(figure: remaining?.clockText ?? "—", template: "88:88")
    }

    static func calendar(_ events: [AgendaEvent], at now: Date, options: [String: String]) -> ItemContent {
        let next = CalendarItem.next(
            in: events,
            at: now,
            windowHours: options.number(ItemOption.calendarWindowHours, default: 4),
            skipsAllDay: options.flag(ItemOption.skipsAllDay, default: true)
        )
        let limit = options.number(ItemOption.titleLength, default: 20)
        return ItemContent(
            figure: next.map { CalendarItem.title($0.title, limit: limit) } ?? "—",
            template: String(repeating: "n", count: limit)
        )
    }

    static func endsIn(_ events: [AgendaEvent], at now: Date, options: [String: String]) -> ItemContent {
        let state = EndsInState(
            events: events,
            at: now,
            includeAllDay: options.flag(ItemOption.includesAllDay, default: false)
        )
        guard let remaining = state.current.first?.end.timeIntervalSince(now) else {
            var free = ItemContent(figure: loc("Free"), template: "8:88:88")
            free.isHidden = !options.flag(ItemOption.showsFree, default: true)
            return free
        }
        let warnAt = TimeInterval(options.number(ItemOption.warnMinutes, default: 5) * 60)
        let urgency = EndsInUrgency(remaining: remaining, warnAt: warnAt)
        return ItemContent(
            figure: remaining.clockText,
            alert: urgency == .lastMinute ? Palette.red : urgency == .soon ? Palette.orange : nil,
            template: "8:88:88"
        )
    }

    static func todos(_ store: AgendaStore, at now: Date, options: [String: String]) -> ItemContent {
        let count = TodoFilter.all.apply(to: store.todos, now: now).count
        let isGranted = store.remindersAccess == .granted
        var item = ItemContent(figure: isGranted ? "\(count)" : "—", template: "888")
        item.isHidden = isGranted && count == 0 && options.flag(ItemOption.hidesWhenDone, default: true)
        return item
    }
}

public extension ModuleID {
    /// Items that can leave the menu bar by themselves, so their width is measured again on every read.
    var canHideItself: Bool {
        [.nowPlaying, .battery, .todos, .vpn, .endsIn].contains(self)
    }
}

private extension TimeInterval {
    /// `3:42`.
    var hoursAndMinutes: String {
        UptimeFormat.hoursText(self)
    }
}
