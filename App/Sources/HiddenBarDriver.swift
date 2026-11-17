import AppKit
import GlassWorkCore

/// Runs `HiddenBarMachine` against the real clock, the keyboard and the pointer.
///
/// It sleeps until the machine's next deadline instead of polling, and listens for pointer moves only while
/// "Show on hover" is on.
@MainActor
final class HiddenBarDriver {
    /// Where the separator is: the right edge of its item and the screen it is on.
    struct Placement {
        var separatorMaxX: CGFloat
        var screenMaxY: CGFloat
        var barHeight: CGFloat
    }

    private(set) var machine = HiddenBarMachine()
    /// Called after every change, with the lengths to apply.
    var onChange: ((HiddenBarMachine) -> Void)?
    var placement: (() -> Placement?)?

    private var timer: Task<Void, Never>?
    private var monitors: [Any] = []
    private var showsOnHover = false
    /// Pointer moves below this height are ignored without any other work.
    private var bandMinY = CGFloat.infinity
    private var isInZone = false
    private var screens: NSObjectProtocol?

    func configure(_ settings: HidingSettings) {
        machine.configure(settings)
        setHoverMonitoring(settings.isEnabled && settings.showsOnHover)
        changed()
    }

    /// A click on the separator or the shortcut.
    func toggle(option: Bool) {
        machine.toggle(option: option, now: Date())
        changed()
    }

    func revealIfCollapsed() {
        guard machine.isCollapsed else { return }
        machine.revealIfCollapsed(now: Date())
        changed()
    }

    /// Opens what an item is in so it can be pressed. Never closes anything.
    func reveal(includingAlwaysHidden all: Bool) {
        guard machine.isCollapsed || (all && machine.phase == .revealed) else { return }
        machine.toggle(option: all, now: Date())
        changed()
    }

    private func changed() {
        refreshBand()
        onChange?(machine)
        timer?.cancel()
        timer = nil
        guard let due = machine.nextDeadline else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.deadlineReached()
        }
    }

    private func deadlineReached() {
        let command = NSEvent.modifierFlags.contains(.command)
        machine.tick(now: Date(), commandHeld: command, pointerInZone: pointerInZone())
        changed()
    }

    // MARK: Pointer

    private func setHoverMonitoring(_ wanted: Bool) {
        guard wanted != showsOnHover else { return }
        showsOnHover = wanted
        if wanted {
            let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            }
            // The status items are this app's own windows, which the global monitor does not see.
            let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved() }
                return event
            }
            monitors = [global, local].compactMap(\.self)
            screens = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshBand() }
            }
        } else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            if let screens {
                NotificationCenter.default.removeObserver(screens)
            }
            screens = nil
            isInZone = false
        }
    }

    private func refreshBand() {
        guard showsOnHover, let place = placement?() else { return }
        bandMinY = place.screenMaxY - place.barHeight
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        guard point.y >= bandMinY else {
            // Outside the bar's height: nothing to do unless the pointer was just at the separator.
            if isInZone {
                isInZone = false
                machine.pointerMoved(inZone: false, now: Date())
                changed()
            }
            return
        }
        let inZone = pointerInZone()
        guard inZone || isInZone else { return }
        isInZone = inZone
        machine.pointerMoved(inZone: inZone, now: Date())
        changed()
    }

    private func pointerInZone() -> Bool {
        guard let place = placement?() else { return false }
        return HiddenBarZone.contains(
            NSEvent.mouseLocation,
            separatorMaxX: place.separatorMaxX,
            screenMaxY: place.screenMaxY,
            barHeight: place.barHeight
        )
    }
}
