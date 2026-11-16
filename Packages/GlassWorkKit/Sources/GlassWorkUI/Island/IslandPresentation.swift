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
        case .charging, .keepAwake: Palette.green
        case .nowPlaying: artworkTint
        case .copied: Palette.teal
        case .weather: Palette.blue
        case .levels(_, .volume): Palette.pink
        case .levels(_, .brightness): Palette.yellow
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
        case .devServers(.serverAppeared): "play.fill"
        case .charging: "bolt.fill"
        case .keepAwake: "cup.and.heat.waves.fill"
        case .nowPlaying: "music.note"
        case .copied: "doc.on.clipboard"
        case .weather: "cloud.rain"
        case let .levels(levels, .volume): levels.isSilent ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .levels(_, .brightness): "sun.max.fill"
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
        case let .devServers(.containerExited(container)): container.name
        case let .devServers(.serverAppeared(server)): server.tool ?? server.process
        case .charging, .keepAwake, .nowPlaying: ""
        case .copied: loc("Copied")
        case .weather: loc("Weather")
        case .levels: ""
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
        case let .devServers(.containerExited(container)): containerTitle(container)
        case let .devServers(.serverAppeared(server)): loc("\(server.tool ?? server.process) server is up")
        case .charging: loc("Charging")
        case .keepAwake: loc("Keep Awake")
        case let .nowPlaying(session): session.track.title
        case .copied: loc("Copied")
        case .weather: loc("Weather")
        case .levels(_, .volume): loc("Volume")
        case .levels(_, .brightness): loc("Brightness")
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
        case let .devServers(.containerExited(container)): container.status
        case let .devServers(.serverAppeared(server)): ":\(server.port)"
        case let .charging(battery): Format.percent(battery.charge)
        case let .keepAwake(end): PlaybackTime.text(end.timeIntervalSince(now))
        case let .nowPlaying(session): PlaybackTime.text(session.position(at: now))
        case let .copied(entry): clipboardKind(entry.kind)
        case let .weather(report): Format.temperature(report.current.temperature)
        case let .levels(levels, .volume): volumeText(levels)
        case let .levels(levels, .brightness): Format.percent(levels.brightness ?? 0)
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
        }
    }

    private func volumeText(_ levels: SystemLevels) -> String {
        if levels.isMuted {
            return loc("Muted")
        }
        return Format.percent(levels.volume ?? 0)
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
