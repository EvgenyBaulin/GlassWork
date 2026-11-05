import Foundation
import IOKit.pwr_mgt
import Observation

/// Live state of the small everyday modules.
@MainActor
@Observable
public final class EverydayStore {
    public private(set) var data: EverydayData
    public private(set) var isKeepingAwake = false
    /// When Keep Awake stops by itself. Nil keeps it on until it is turned off.
    public private(set) var keepAwakeEnds: Date?
    /// Keeps the Mac running with the screen off. Applies from the next time Keep Awake is turned on.
    @ObservationIgnored public var letsDisplaySleep = false
    /// Applies from the next time Keep Awake is turned on, except for the battery, which is checked all along.
    @ObservationIgnored public var keepAwakeRule = KeepAwakeRule()
    /// Called when a timer reaches zero.
    @ObservationIgnored public var onTimerFinished: ((CountdownTimer) -> Void)?

    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private var assertion: IOPMAssertionID = 0

    public init(store: SnapshotStore = SnapshotStore()) {
        self.store = store
        data = store.read(EverydayData.self, for: EverydayData.key) ?? EverydayData()
    }

    public func update(_ change: (inout EverydayData) -> Void) {
        change(&data)
        try? store.write(data, for: EverydayData.key)
    }

    public func startTimer(title: String, duration: TimeInterval) {
        update { $0.timers.append(CountdownTimer(title: title, duration: duration, start: Date())) }
    }

    /// Removes finished timers and reports them, and ends Keep Awake when its time or the battery runs out.
    public func tick(at date: Date = Date(), battery: BatterySample? = nil) {
        if isKeepingAwake, keepAwakeRule.shouldStop(endingAt: keepAwakeEnds, at: date, battery: battery) {
            toggleKeepAwake(at: date)
        }
        let finished = data.timers.filter { $0.isFinished(at: date) }
        guard !finished.isEmpty else { return }
        update { $0.timers.removeAll { $0.isFinished(at: date) } }
        finished.forEach { onTimerFinished?($0) }
    }

    /// Starts a Pomodoro run, or stops the one under way and keeps its finished rounds.
    public func togglePomodoro(at date: Date = Date()) {
        update { data in
            var session = data.pomodoro ?? PomodoroSession()
            if session.isRunning {
                session.stop(at: date)
            } else {
                session.start(at: date)
            }
            data.pomodoro = session
        }
    }

    public func toggleKeepAwake(at date: Date = Date()) {
        if isKeepingAwake {
            IOPMAssertionRelease(assertion)
            isKeepingAwake = false
            keepAwakeEnds = nil
        } else {
            let status = IOPMAssertionCreateWithProperties(assertionProperties() as CFDictionary, &assertion)
            isKeepingAwake = status == kIOReturnSuccess
            keepAwakeEnds = isKeepingAwake ? keepAwakeRule.end(from: date) : nil
        }
    }

    /// The system lets go by itself at the end, because no tick runs while the Mac sleeps.
    private func assertionProperties() -> [String: Any] {
        let type = letsDisplaySleep
            ? kIOPMAssertionTypePreventUserIdleSystemSleep
            : kIOPMAssertionTypePreventUserIdleDisplaySleep
        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: type,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
            kIOPMAssertionNameKey: "GlassWork Keep Awake",
        ]
        if keepAwakeRule.minutes > 0 {
            properties[kIOPMAssertionTimeoutKey] = keepAwakeRule.minutes * 60
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        return properties
    }
}
