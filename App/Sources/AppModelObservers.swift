import AppKit
import GlassWorkCore

/// What the Mac tells the app: which app is in front, and when the screen, the session or the Mac goes away.
extension AppModel {
    /// Screen time counts only after the user turns it on.
    func observeFrontApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName
            let bundle = app?.bundleURL
            MainActor.assumeIsolated {
                guard let self, self.store.settings.widgets.tracksScreenTime else { return }
                self.monitor.activity.appBecameActive(name, category: Self.category(of: bundle))
            }
        }
        observeLock()
    }

    /// An app run from Downloads or Documents stays uncategorized: opening its bundle would ask for permission.
    private static func category(of bundle: URL?) -> AppCategory {
        guard let bundle, !ProtectedFolders.contains(bundle.path(percentEncoded: false), home: NSHomeDirectory())
        else { return .other }
        let declared = Bundle(url: bundle)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        return AppCategory(appStoreCategory: declared)
    }

    /// Locking keeps the display on for a while, so sleep alone would miss most breaks.
    private func observeLock() {
        let center = DistributedNotificationCenter.default()
        let locked = Notification.Name("com.apple.screenIsLocked")
        let unlocked = Notification.Name("com.apple.screenIsUnlocked")
        center.addObserver(forName: locked, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAway(true) }
        }
        center.addObserver(forName: unlocked, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAway(false) }
        }
    }

    private func screenAway(_ isAway: Bool) {
        guard store.settings.widgets.tracksScreenTime else { return }
        if isAway {
            monitor.activity.screenWentAway()
        } else {
            monitor.activity.screenCameBack()
        }
    }

    /// Nothing is read while the Mac sleeps, the screen is off or locked, or another user is active.
    func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let pause: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let resume: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        // The fan loop keeps running through a locked screen, so only real sleep ends it.
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.fans.willSleep() }
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fans.didWake() }
        }
        for name in pause {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.monitor.stop()
                    self?.clipboard.setPaused(true)
                    self?.screenAway(true)
                }
            }
        }
        for name in resume {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.monitor.start()
                    self?.clipboard.setPaused(false)
                    self?.screenAway(false)
                }
            }
        }
    }
}
