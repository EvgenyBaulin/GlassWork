import Foundation
import IOKit.pwr_mgt
import Observation

/// Live state of the small everyday modules.
@MainActor
@Observable
public final class EverydayStore {
    public private(set) var data: EverydayData
    public private(set) var isKeepingAwake = false
    /// Keeps the Mac running with the screen off. Applies from the next time Keep Awake is turned on.
    @ObservationIgnored public var letsDisplaySleep = false
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

    /// Removes finished timers and reports them.
    public func tick(at date: Date = Date()) {
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

    public func toggleKeepAwake() {
        if isKeepingAwake {
            IOPMAssertionRelease(assertion)
            isKeepingAwake = false
        } else {
            let type = letsDisplaySleep
                ? kIOPMAssertionTypePreventUserIdleSystemSleep
                : kIOPMAssertionTypePreventUserIdleDisplaySleep
            let status = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "GlassWork Keep Awake" as CFString,
                &assertion
            )
            isKeepingAwake = status == kIOReturnSuccess
        }
    }
}
