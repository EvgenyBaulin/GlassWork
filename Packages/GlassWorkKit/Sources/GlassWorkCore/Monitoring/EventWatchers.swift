import AppKit
import Foundation
import IOKit.ps

/// Calls back on the main actor when the power source changes: plugging in, unplugging, the charge moving.
@MainActor
final class PowerSourceWatcher {
    private var source: CFRunLoopSource?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let watcher = Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue()
            // The source runs on the main run loop.
            MainActor.assumeIsolated { watcher.onChange() }
        }
        guard let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        source = created
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = nil
    }

    isolated deinit {
        // The callback holds this object unretained, so the source has to go before it does.
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}

/// Calls back on the main actor when a volume is mounted, unmounted or renamed.
@MainActor
final class VolumeWatcher {
    private var tokens: [any NSObjectProtocol] = []

    init(onChange: @escaping @MainActor () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange() }
            }
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach(center.removeObserver)
        tokens = []
    }

    isolated deinit {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach(center.removeObserver)
    }
}
