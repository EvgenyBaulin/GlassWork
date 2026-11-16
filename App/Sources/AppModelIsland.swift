import AppKit
import GlassWorkCore
import GlassWorkUI

extension AppModel {
    func updateIsland() {
        guard store.settings.island.isEnabled else { return }
        var input = IslandInput(monitor: monitor, alerts: store.settings.alerts)
        input.levels = islandFeeds.levels
        input.downloads = islandFeeds.downloads
        if let batteries = islandFeeds.deviceBatteries {
            input.deviceBatteries = batteries
        }
        island.update(input: input, now: Date())
    }

    var islandActions: IslandActions {
        var actions = IslandActions(
            joinMeeting: { NSWorkspace.shared.open($0) },
            snooze: { [weak self] in
                guard let self, island.queue.pages.indices.contains(self.island.page) else { return }
                let event = island.queue.pages[island.page]
                island.snoozeMeeting(id: event.id, now: Date())
            },
            // There is no outgoing meeting notification API. The optional Running Late button stays hidden.
            addMinute: { [weak self] in self?.extendIslandTimer() },
            stopTimers: { [weak self] in self?.stopIslandTimer() },
            addTimer: { [weak self] in self?.showPanelAtPointer(.timers) },
            pin: { [weak self] id in
                guard let self, let entry = monitor.clipboard.history.entries.first(where: { $0.id == id })
                else { return }
                monitor.clipboard.togglePin(entry)
                updateIsland()
            },
            openHistory: { [weak self] in self?.clipboard.showQuickPaste() },
            fansToMax: { [weak self] in self?.fans.select(.max) },
            openActivityMonitor: Self.openActivityMonitor,
            showTop: Self.openActivityMonitor,
            // No public API reconnects a VPN, so the card offers Network settings only.
            reconnectVPN: nil,
            openNetworkSettings: Self.openNetworkSettings,
            // DeveloperStore exposes readings only. Optional restart/log buttons stay hidden.
            openURL: { NSWorkspace.shared.open($0) },
            playPause: { [weak self] in self?.monitor.nowPlaying.perform(.toggle) },
            next: { [weak self] in self?.monitor.nowPlaying.perform(.next) },
            previous: { [weak self] in self?.monitor.nowPlaying.perform(.previous) },
            seek: { [weak self] in self?.monitor.nowPlaying.perform(.seek($0)) },
            setVolume: { [weak self] in
                SystemLevelsReader.setVolume($0)
                self?.islandFeeds.refreshLevels()
            },
            extendKeepAwake: { [weak self] in
                self?.monitor.everyday.extendKeepAwake(by: $0)
                self?.updateIsland()
            },
            stopKeepAwake: { [weak self] in
                guard let self, monitor.everyday.isKeepingAwake else { return }
                monitor.everyday.toggleKeepAwake()
                updateIsland()
            },
            dismiss: { [weak self] in self?.island.dismiss(id: $0) },
            openPage: { [weak self] in self?.island.showPage($0) }
        )
        // The initializer has no brightness parameter; the slider stays hidden without a settable display.
        if SystemLevelsReader.canSetBrightness {
            actions.setBrightness = { [weak self] in
                SystemLevelsReader.setBrightness($0)
                self?.islandFeeds.refreshLevels()
            }
        }
        return actions
    }

    /// The timer the card's buttons act on: one that already rang, else the next to ring.
    private func islandTimer(now: Date) -> CountdownTimer? {
        let running = monitor.everyday.data.timers.filter { !$0.isPaused && $0.endDate != nil }
        let rang = running.filter { ($0.endDate ?? .distantFuture) <= now }
        return (rang.isEmpty ? running : rang).min { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    /// One more minute from now for a timer that already rang, one more minute on top for the others.
    private func extendIslandTimer() {
        let now = Date()
        guard let timer = islandTimer(now: now) else { return }
        monitor.everyday.update { data in
            guard let index = data.timers.firstIndex(where: { $0.id == timer.id }),
                  let end = data.timers[index].endDate else { return }
            data.timers[index].endDate = max(end, now).addingTimeInterval(60)
            data.timers[index].duration += 60
        }
        updateIsland()
    }

    /// Stops the timers that rang, or the next one if none did; the others keep running.
    private func stopIslandTimer() {
        let now = Date()
        guard let timer = islandTimer(now: now) else { return }
        let rang = (timer.endDate ?? .distantFuture) <= now
        monitor.everyday.update { data in
            data.timers.removeAll { candidate in
                rang ? !candidate.isPaused && (candidate.endDate ?? .distantFuture) <= now : candidate.id == timer.id
            }
        }
        updateIsland()
    }

    private static func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private static func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
