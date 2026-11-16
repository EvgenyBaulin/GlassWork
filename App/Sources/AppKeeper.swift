import AppKit
import GlassWorkCore
import ServiceManagement

/// Launch at login through a LaunchAgent that also brings GlassWork back after a crash.
///
/// launchd starts the app at login and again whenever it exits by a crash (`KeepAlive: SuccessfulExit = false`).
/// ⌘Q, Quit in the menu and SIGTERM from `make install` or the updater are normal exits and stay down.
/// A launch from Finder hands over to the agent, so the running copy is always the watched one.
@MainActor
enum AppKeeper {
    static let label = "io.github.evgenybaulin.GlassWork.Keeper"
    private static let guardKey = "keeper.restartGuard"
    private static let showWindowKey = "keeper.showWindowAfterHandover"

    private static var agent: SMAppService {
        .agent(plistName: "\(label).plist")
    }

    static var launchedByKeeper: Bool {
        ProcessInfo.processInfo.environment["GW_KEEPER"] == "1"
    }

    // MARK: Launch at login

    static var launchesAtLogin: Bool {
        agent.status == .enabled || SMAppService.mainApp.status == .enabled
    }

    static func setLaunchesAtLogin(_ enabled: Bool) {
        if enabled {
            // Both at once would start two copies at login.
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
            try? agent.register()
        } else {
            try? agent.unregister()
            try? SMAppService.mainApp.unregister()
        }
    }

    // MARK: Launch

    enum Start {
        case run(showWindow: Bool)
        case exit
    }

    /// Runs before anything else at launch.
    static func start() -> Start {
        #if DEBUG
            // A debug build shares the bundle ID: it must neither hand over to nor give way to the installed app.
            .run(showWindow: false)
        #else
            startRelease()
        #endif
    }

    private static func startRelease() -> Start {
        // Earlier versions launched at login as a login item; the agent replaces it.
        if SMAppService.mainApp.status == .enabled {
            setLaunchesAtLogin(true)
        }
        if launchedByKeeper {
            return startUnderKeeper()
        }
        if let other = otherCopy() {
            other.activate()
            return .exit
        }
        if agent.status == .enabled, handOver() {
            UserDefaults.standard.set(true, forKey: showWindowKey)
            return .exit
        }
        var guardian = restartGuard
        _ = guardian.launch(at: Date(), byKeeper: false)
        restartGuard = guardian
        return .run(showWindow: false)
    }

    private static func startUnderKeeper() -> Start {
        // A copy opened by hand may still be quitting after handing over.
        let deadline = Date().addingTimeInterval(3)
        while otherCopy() != nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if otherCopy() != nil {
            return .exit
        }
        var guardian = restartGuard
        let decision = guardian.launch(at: Date(), byKeeper: true)
        restartGuard = guardian
        guard decision == .run else { return .exit }
        let showWindow = UserDefaults.standard.bool(forKey: showWindowKey)
        UserDefaults.standard.removeObject(forKey: showWindowKey)
        return .run(showWindow: showWindow)
    }

    /// Starts the agent's copy; this one then quits.
    private static func handOver() -> Bool {
        let launchctl = Process()
        launchctl.executableURL = URL(filePath: "/bin/launchctl")
        launchctl.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
        guard (try? launchctl.run()) != nil else { return false }
        launchctl.waitUntilExit()
        return launchctl.terminationStatus == 0
    }

    private static func otherCopy() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ownPID && !$0.isTerminated }
    }

    // MARK: Quit

    private static var signalSource: DispatchSourceSignal?

    /// SIGTERM, as from `pkill`, quits like ⌘Q: a killed process would count as a crash and come straight back.
    static func quitOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        signalSource = source
    }

    static func didQuit() {
        var guardian = restartGuard
        guardian.quit()
        restartGuard = guardian
    }

    private static var restartGuard: RestartGuard {
        get {
            UserDefaults.standard.data(forKey: guardKey)
                .flatMap { try? JSONDecoder().decode(RestartGuard.self, from: $0) } ?? RestartGuard()
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: guardKey)
        }
    }
}
