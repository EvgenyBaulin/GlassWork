import Foundation
import IOKit.pwr_mgt
import Observation

/// Live state of the small everyday modules.
@MainActor
@Observable
public final class EverydayStore {
    public private(set) var data: EverydayData
    public private(set) var isKeepingAwake = false
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

    public func toggleKeepAwake() {
        if isKeepingAwake {
            IOPMAssertionRelease(assertion)
            isKeepingAwake = false
        } else {
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "GlassWork Keep Awake" as CFString,
                &assertion
            )
            isKeepingAwake = status == kIOReturnSuccess
        }
    }
}
