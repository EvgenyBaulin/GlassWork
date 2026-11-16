import Foundation

extension SystemMonitor {
    /// How long the loop sleeps: until the earliest read falls due, a second at least and 30 s at most.
    func waitUntilNextRead() async -> TimeInterval {
        let now = Date()
        var plan = await sampler.plan(for: demand, at: now)
        if demand.battery {
            plan.dates.append(ReadSchedule.eventDrivenDate(
                last: lastBattery, interval: eventDrivenInterval, event: batteryEvent, now: now
            ))
        }
        if demand.disk {
            plan.dates.append(ReadSchedule.eventDrivenDate(
                last: lastVolumes, interval: eventDrivenInterval, event: volumesEvent, now: now
            ))
        }
        if demand.slowProcesses {
            plan.dates.append(ReadSchedule.dueDate(last: lastSlow, pace: slowInterval, now: now))
        }
        if demand.devices {
            plan.dates.append(ReadSchedule.dueDate(last: lastDevices, pace: Self.occasionalInterval, now: now))
        }
        if demand.timeMachine {
            plan.dates.append(ReadSchedule.dueDate(last: lastTimeMachine, pace: Self.occasionalInterval, now: now))
        }
        plan.everyTick = plan.everyTick || storesNeedEveryTick
        return ReadSchedule.nextWake(now: now, tickInterval: effectiveInterval, plan: plan).timeIntervalSince(now)
    }

    /// Timers and Keep Awake have to end on time, the adapter has to stop, and developer modules and app lists keep
    /// their own paces. All of them look at the clock on each tick, so the loop keeps ticking for them.
    var storesNeedEveryTick: Bool {
        !everyday.data.timers.isEmpty || everyday.isKeepingAwake || demand.nowPlaying || nowPlaying.isRunning
            || demand.liveApps || !demand.developer.isEmpty
    }

    /// A panel or the main window is open (the flag the developer modules use for it).
    var panelIsOpen: Bool {
        demand.developerLive
    }

    /// Battery and volumes follow events; a panel keeps the old pace and the rest has a slow safety net.
    var eventDrivenInterval: TimeInterval {
        ReadSchedule.eventDrivenInterval(panelOpen: panelIsOpen, panelInterval: slowInterval)
    }

    /// Starts and stops the event sources with the demand.
    func watchEvents() {
        if demand.battery, powerWatcher == nil {
            powerWatcher = PowerSourceWatcher { [weak self] in
                self?.batteryEvent = true
                self?.sleeper.wake()
            }
        } else if !demand.battery {
            powerWatcher = nil
        }
        if demand.disk, volumeWatcher == nil {
            volumeWatcher = VolumeWatcher { [weak self] in
                self?.volumesEvent = true
                self?.sleeper.wake()
            }
        } else if !demand.disk {
            volumeWatcher = nil
        }
    }
}
