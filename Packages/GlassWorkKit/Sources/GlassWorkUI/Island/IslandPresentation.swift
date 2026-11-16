import AppKit
import GlassWorkCore
import SwiftUI

/// Text and accents shared by both sizes of the same event.
struct IslandPresentation {
    let event: IslandEvent
    let now: Date
    var locale = Locale.current
    var timeZone = TimeZone.current

    var tint: Color {
        switch event.detail {
        case .meeting, .devServers: Palette.red
        case .inProgress: Palette.blue
        case .timers: Palette.orange
        case .systemAlert: event.context.isOverheated ? Palette.orange : Palette.red
        case .network(.pingRecovered): Palette.green
        case .network: Palette.red
        case let .build(reading): buildTint(reading)
        case .charging, .keepAwake: Palette.green
        case .nowPlaying: artworkTint
        case .copied: Palette.teal
        case .shelfDrop: Palette.purple
        case .weather, .downloads: Palette.blue
        case .levels(_, .volume): Palette.pink
        case .levels(_, .brightness): Palette.yellow
        case .headphones: Palette.green
        case .focus: Palette.purple
        }
    }

    private var artworkTint: Color {
        guard let data = event.context.artwork, let bitmap = NSBitmapImageRep(data: data),
              let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        else { return Palette.pink }
        return Color(nsColor: color)
    }

    var symbol: String {
        switch event.detail {
        case .meeting, .inProgress: "calendar"
        case .timers: "timer"
        case .systemAlert, .devServers(.containerExited): "exclamationmark.triangle"
        case .network: "globe"
        case .build: "hammer.fill"
        case .devServers(.serverAppeared): "play.fill"
        case .charging: "bolt.fill"
        case .keepAwake: "cup.and.heat.waves.fill"
        case .nowPlaying: "music.note"
        case .copied: "doc.on.clipboard"
        case .shelfDrop: "tray"
        case .weather: "cloud.rain"
        case let .levels(levels, .volume): levels.isSilent ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .levels(_, .brightness): "sun.max.fill"
        case .downloads: "arrow.down"
        case .headphones: "airpodspro"
        case let .focus(reading): focusSymbol(reading)
        }
    }

    var compactLabel: String {
        switch event.detail {
        case let .meeting(meeting): minutes(meeting.start.timeIntervalSince(now))
        case let .inProgress(meeting): meeting.title
        case let .timers(timers): soonest(timers)?.title ?? loc("Timers")
        case .systemAlert:
            if event.context.isOverheated {
                loc("Hot")
            } else {
                loc("Disk")
            }
        case .network(.wifiLost): loc("Wi-Fi")
        case .network(.vpnOff): loc("VPN")
        case .network(.pingRecovered): loc("Ping")
        case let .build(reading): buildName(reading) ?? loc("Build")
        case let .devServers(.containerExited(container)): container.name
        case let .devServers(.serverAppeared(server)): server.tool ?? server.process
        case .charging, .keepAwake, .nowPlaying: ""
        case .copied: loc("Copied")
        case .shelfDrop: loc("Shelf")
        case .weather: loc("Weather")
        case .levels, .headphones: ""
        case let .focus(reading): reading.name ?? loc("Focus")
        case .downloads: ""
        }
    }

    var title: String {
        switch event.detail {
        case let .meeting(meeting), let .inProgress(meeting): meeting.title
        case let .timers(timers): loc("\(timers.count) timers")
        case .systemAlert:
            if !event.context.isOverheated {
                loc("Disk almost full")
            } else {
                loc("Mac is running hot")
            }
        case .network(.wifiLost): loc("Wi-Fi lost")
        case .network(.vpnOff): loc("VPN disconnected")
        case .network(.pingRecovered): loc("Ping back to normal")
        case let .build(reading): buildTitle(reading)
        case let .devServers(.containerExited(container)): containerTitle(container)
        case let .devServers(.serverAppeared(server)): loc("\(server.tool ?? server.process) server is up")
        case .charging: loc("Charging")
        case .keepAwake: loc("Keep Awake")
        case let .nowPlaying(session): session.track.title
        case .copied: loc("Copied")
        case .shelfDrop: loc("Added to the Shelf")
        case .weather: loc("Weather")
        case .levels(_, .volume): loc("Volume")
        case .levels(_, .brightness): loc("Brightness")
        case let .downloads(files): downloadsTitle(files)
        case let .headphones(name, _): name
        case let .focus(reading): focusTitle(reading)
        }
    }

    var value: String {
        switch event.detail {
        case let .meeting(meeting): loc("in \(minutes(meeting.start.timeIntervalSince(now)))")
        case let .inProgress(meeting): PlaybackTime.text(meeting.end.timeIntervalSince(now))
        case let .timers(timers): soonest(timers).map(timerValue) ?? ""
        case let .systemAlert(alert):
            if event.context.isOverheated {
                alert.averageCPU.map { Format.temperature($0) } ?? ""
            } else {
                alert.lowSpaceVolume.map { Format.size(Double($0.free)) } ?? ""
            }
        case .network(.wifiLost): loc("lost")
        case .network(.vpnOff): loc("off")
        case let .network(.pingRecovered(outcome)): pingValue(outcome)
        case let .build(reading): buildValue(reading)
        case let .devServers(.containerExited(container)): container.status
        case let .devServers(.serverAppeared(server)): ":\(server.port)"
        case let .charging(battery): Format.percent(battery.charge)
        case let .keepAwake(end): PlaybackTime.text(end.timeIntervalSince(now))
        case let .nowPlaying(session): PlaybackTime.text(session.position(at: now))
        case let .copied(entry): clipboardKind(entry.kind)
        case let .shelfDrop(count): "+\(count)"
        case let .weather(report): Format.temperature(report.current.temperature)
        case let .levels(levels, .volume): volumeText(levels)
        case let .levels(levels, .brightness): Format.percent(levels.brightness ?? 0)
        case let .downloads(files): downloadsValue(files)
        case let .headphones(_, batteries): headphonesValue(batteries)
        case let .focus(reading): focusValue(reading)
        }
    }

    var compactValue: String {
        switch event.detail {
        case let .meeting(meeting): return meeting.callURL == nil ? value : loc("Join")
        case let .devServers(.containerExited(container)):
            if let code = exitCode(container) {
                return loc("exit \(code)")
            }
            return loc("exited")
        case let .build(.finished(result)): return buildCompactOutcome(result)
        default: return value
        }
    }

    var subtitle: String {
        switch event.detail {
        case let .meeting(meeting), let .inProgress(meeting):
            [meeting.location, "\(clock(meeting.start))–\(clock(meeting.end))"].compactMap(\.self)
                .joined(separator: " · ")
        case let .timers(timers):
            if let end = soonest(timers)?.endDate {
                loc("next ends at \(clock(end))")
            } else {
                ""
            }
        case let .systemAlert(alert):
            [
                alert.averageCPU.map { loc("CPU \(Format.temperature($0))") },
                event.context.fanRPM.map { loc("fans \(Format.groupedRPM($0)) rpm") },
            ]
            .compactMap(\.self).joined(separator: " · ")
        case .network(.wifiLost): loc("Reconnecting…")
        case let .network(.vpnOff(vpn)): vpn.services.first?.name ?? ""
        case let .network(.pingRecovered(outcome)): pingValue(outcome)
        case let .build(reading): buildSubtitle(reading)
        case let .devServers(.containerExited(container)):
            [container.image, event.context.dockerContext].compactMap(\.self).joined(separator: " · ")
        case let .devServers(.serverAppeared(server)): server.project
        case let .charging(battery):
            [
                battery.minutesRemaining.map { loc("full at \(clock(now.addingTimeInterval(Double($0) * 60)))") },
                battery.adapterWatts.map { loc("\($0) W adapter") },
            ].compactMap(\.self).joined(separator: " · ")
        case let .keepAwake(end):
            [loc("until \(clock(end))"), event.context.keepAwakeIncludesDisplay.map {
                if $0 {
                    loc("Mac + display")
                } else {
                    loc("Mac only")
                }
            }].compactMap(\.self).joined(separator: " · ")
        case let .nowPlaying(session):
            [session.track.artist, session.track.album].compactMap(\.self).joined(separator: " — ")
        case let .copied(entry):
            [entry.appName.map { loc("from \($0)") }, Format.size(Double(entry.byteCount))]
                .compactMap(\.self).joined(separator: " · ")
        case let .weather(report): report.place.name
        case let .levels(levels, .volume): levels.outputName ?? ""
        case .levels(_, .brightness): loc("Built-in display")
        case let .downloads(files): files.count == 1 ? files[0].name : ""
        case let .shelfDrop(count): filesText(count)
        case .headphones: loc("Connected")
        case .focus: ""
        }
    }

    /// The mode's own symbol when this system has it, else the moon of Do Not Disturb.
    private func focusSymbol(_ reading: FocusReading) -> String {
        if let symbol = reading.symbol, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
            return symbol
        }
        return "moon.fill"
    }

    private func focusValue(_ reading: FocusReading) -> String {
        if reading.isOn {
            return loc("On")
        }
        return loc("Off")
    }

    private func focusTitle(_ reading: FocusReading) -> String {
        switch (reading.name, reading.isOn) {
        case let (name?, true): loc("\(name) on")
        case let (name?, false): loc("\(name) off")
        case (nil, true): loc("Focus on")
        case (nil, false): loc("Focus off")
        }
    }

    private func buildTint(_ reading: BuildReading) -> Color {
        guard case let .finished(result) = reading else { return Palette.blue }
        return result.succeeded ? Palette.green : Palette.red
    }

    private func buildName(_ reading: BuildReading) -> String? {
        switch reading {
        case let .running(run): run.name
        case let .finished(result): result.name
        }
    }

    private func buildTitle(_ reading: BuildReading) -> String {
        switch reading {
        case let .running(run): run.name.map { loc("Building \($0)") } ?? loc("Building")
        case let .finished(result):
            if result.succeeded {
                loc("Build succeeded")
            } else {
                loc("Build failed")
            }
        }
    }

    /// Time so far while it runs, the outcome once it ended.
    private func buildValue(_ reading: BuildReading) -> String {
        switch reading {
        case let .running(run): PlaybackTime.text(max(now.timeIntervalSince(run.started), 0))
        case let .finished(result): buildOutcome(result)
        }
    }

    /// Short enough for a wing, which sizes itself for proportional text although the value is monospaced.
    private func buildCompactOutcome(_ result: BuildResult) -> String {
        if result.succeeded {
            return loc("done")
        }
        return result.errors > 0 ? loc("\(result.errors) err") : loc("failed")
    }

    private func buildOutcome(_ result: BuildResult) -> String {
        if result.succeeded {
            return loc("done")
        }
        return result.errors > 0 ? loc("\(result.errors) errors") : loc("failed")
    }

    private func buildSubtitle(_ reading: BuildReading) -> String {
        guard case let .finished(result) = reading else { return "" }
        return [
            result.errors > 0 ? loc("\(result.errors) errors") : nil,
            result.warnings > 0 ? loc("\(result.warnings) warnings") : nil,
            loc("took \(PlaybackTime.text(result.duration))"),
        ].compactMap(\.self).joined(separator: " · ")
    }

    private func filesText(_ count: Int) -> String {
        if count == 1 {
            return loc("1 file")
        }
        return loc("\(count) files")
    }

    /// The buds, not the case, which charges them.
    private func headphonesValue(_ batteries: [DeviceBattery]) -> String {
        let buds = batteries.filter { !$0.name.lowercased().hasSuffix("case") }
        return (buds.isEmpty ? batteries : buds).map(\.charge).min().map { Format.percent($0) } ?? ""
    }

    private func volumeText(_ levels: SystemLevels) -> String {
        if levels.isMuted {
            return loc("Muted")
        }
        return Format.percent(levels.volume ?? 0)
    }

    private func downloadsTitle(_ files: [DockFile]) -> String {
        let active = files.filter(\.isDownloading).count
        if active == 0 {
            return files.count == 1 ? loc("Downloaded") : loc("Downloaded \(files.count) files")
        }
        return active == 1 ? loc("Downloading") : loc("Downloading \(active) files")
    }

    private func downloadsValue(_ files: [DockFile]) -> String {
        guard files.contains(where: \.isDownloading) else { return loc("done") }
        return DockFiles.overallProgress(files).map { Format.percent($0) } ?? "…"
    }

    func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    func minutes(_ seconds: TimeInterval) -> String {
        loc("\(Int(max(seconds, 0) / 60)) min")
    }

    func soonest(_ timers: [CountdownTimer]) -> CountdownTimer? {
        let running = timers.filter { !$0.isPaused && !$0.isFinished(at: now) }
        return running.min { $0.remaining(at: now) < $1.remaining(at: now) } ?? timers.first
    }

    func timerValue(_ timer: CountdownTimer) -> String {
        if timer.isFinished(at: now), let end = timer.endDate {
            return "+\(PlaybackTime.text(now.timeIntervalSince(end)))"
        }
        let text = PlaybackTime.text(timer.remaining(at: now))
        return text.count < 5 ? "0\(text)" : text
    }

    func pingValue(_ outcome: PingOutcome) -> String {
        if case let .reply(milliseconds) = outcome {
            return loc("\(Int(milliseconds)) ms")
        }
        return loc("lost")
    }

    private func exitCode(_ container: DockerContainer) -> String? {
        container.status.split(separator: "(").dropFirst().first?.split(separator: ")").first.map(String.init)
    }

    private func containerTitle(_ container: DockerContainer) -> String {
        if let code = exitCode(container) {
            return loc("Container \(container.name) exited (\(code))")
        }
        return loc("Container \(container.name) exited")
    }

    func nextDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
    }

    private func clipboardKind(_ kind: ClipboardKind) -> String {
        switch kind {
        case .text: loc("Text")
        case .link: loc("Link")
        case .file: loc("File")
        case .color: loc("Colour")
        case .image: loc("PNG")
        }
    }
}
