@testable import GlassWorkCore
import Testing

private let own = QuitPolicy.Identity(pid: 500, bundleID: "io.github.evgenybaulin.GlassWork")

private func isProtected(_ target: QuitTarget) -> Bool {
    QuitPolicy.isProtected(target, own: own)
}

struct QuitPolicyTests {
    @Test
    func anOrdinaryAppCanQuit() {
        #expect(!isProtected(QuitTarget(
            pid: 900,
            name: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            path: "/Applications/Slack.app"
        )))
    }

    @Test
    func appsMacOSShipsCanQuit() {
        #expect(!isProtected(QuitTarget(pid: 900, name: "Music", path: "/System/Applications/Music.app")))
        #expect(!isProtected(QuitTarget(
            pid: 900,
            name: "Safari",
            path: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        )))
    }

    @Test
    func glassWorkItselfStays() {
        #expect(isProtected(QuitTarget(pid: 500, name: "Whatever")))
        #expect(isProtected(QuitTarget(pid: 901, name: "X", bundleID: own.bundleID)))
        #expect(isProtected(QuitTarget(pid: 901, name: "X", bundleID: "io.github.evgenybaulin.GlassWork.Widgets")))
        #expect(isProtected(QuitTarget(pid: 901, name: "GlassWorkFanHelper")))
        #expect(isProtected(QuitTarget(pid: 901, name: "GlassWorkFanHelp")))
    }

    @Test
    func theKernelAndLaunchdStay() {
        #expect(isProtected(QuitTarget(pid: 0, name: "anything")))
        #expect(isProtected(QuitTarget(pid: 1, name: "anything")))
        #expect(isProtected(QuitTarget(pid: -1, name: "anything")))
    }

    @Test(arguments: ["kernel_task", "WindowServer", "loginwindow", "Dock", "Finder", "SystemUIServer", "launchd"])
    func criticalNamesStay(name: String) {
        #expect(isProtected(QuitTarget(pid: 900, name: name)))
    }

    @Test(arguments: [
        "/System/Library/CoreServices/Finder.app",
        "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
        "/usr/libexec/trustd",
        "/usr/sbin/bluetoothd",
        "/sbin/launchd",
    ])
    func whatMacOSRunsForItselfStays(path: String) {
        #expect(isProtected(QuitTarget(pid: 900, name: "x", path: path)))
    }

    @Test
    func aToolInUsrLocalCanQuit() {
        #expect(!isProtected(QuitTarget(pid: 900, name: "node", path: "/usr/local/bin/node")))
    }
}

struct DockAppCommandTests {
    @Test
    func anAppThatIsNotRunningCanOnlyOpen() {
        #expect(DockAppCommand.offered(isRunning: false, canQuit: false) == [.open, .showInFinder])
    }

    @Test
    func aRunningAppCanQuitAndForceQuit() {
        let commands = DockAppCommand.offered(isRunning: true, canQuit: true)
        #expect(commands.contains(.quit))
        #expect(commands.contains(.forceQuit))
    }

    @Test
    func aProtectedAppGetsNeither() {
        let commands = DockAppCommand.offered(isRunning: true, canQuit: false)
        #expect(!commands.contains(.quit))
        #expect(!commands.contains(.forceQuit))
        #expect(commands.contains(.hide))
    }
}

/// Records what would have been sent. No real process is involved.
private final class FakeQuitSystem: QuitSystem {
    var holders: [Int32: QuitTarget] = [:]
    var answer = true
    var stopped: [(pid: Int32, force: Bool)] = []

    func identity(of pid: Int32) -> QuitTarget? {
        holders[pid]
    }

    func stop(_ pid: Int32, force: Bool) -> Bool {
        stopped.append((pid, force))
        return answer
    }
}

struct QuitServiceTests {
    private let slack = QuitTarget(pid: 900, name: "Slack", bundleID: "com.tinyspeck.slackmacgap")

    private func service(_ system: FakeQuitSystem) -> QuitService {
        QuitService(system: system, own: own)
    }

    @Test
    func sendsTheRightKindOfQuit() {
        let system = FakeQuitSystem()
        system.holders[900] = slack
        #expect(service(system).quit(slack, force: false) == .sent)
        #expect(service(system).quit(slack, force: true) == .sent)
        #expect(system.stopped.map(\.force) == [false, true])
    }

    @Test
    func aProtectedTargetNeverReachesTheSystem() {
        let system = FakeQuitSystem()
        let finder = QuitTarget(pid: 901, name: "Finder", bundleID: "com.apple.finder")
        system.holders[901] = finder
        #expect(service(system).quit(finder, force: true) == .refused)
        #expect(service(system).quit(QuitTarget(pid: 500, name: "GlassWork"), force: true) == .refused)
        #expect(system.stopped.isEmpty)
    }

    @Test
    func aPidThatIsGoneIsNotSignalled() {
        let system = FakeQuitSystem()
        #expect(service(system).quit(slack, force: true) == .gone)
        #expect(system.stopped.isEmpty)
    }

    @Test
    func aReusedPidIsLeftAlone() {
        let system = FakeQuitSystem()
        system.holders[900] = QuitTarget(pid: 900, name: "Notes", bundleID: "com.apple.Notes")
        #expect(service(system).quit(slack, force: true) == .gone)
        #expect(system.stopped.isEmpty)
    }

    @Test
    func aStaleRowCannotHitSomethingProtected() {
        let system = FakeQuitSystem()
        system.holders[902] = QuitTarget(pid: 902, name: "node", path: "/usr/libexec/node")
        #expect(service(system).quit(QuitTarget(pid: 902, name: "node"), force: true) == .refused)
        #expect(system.stopped.isEmpty)
    }

    @Test
    func aCutNameStillMatches() {
        let system = FakeQuitSystem()
        system.holders[903] = QuitTarget(pid: 903, name: "com.example.very.long.name")
        #expect(service(system).quit(QuitTarget(pid: 903, name: "com.example.very"), force: false) == .sent)
    }

    @Test
    func aRefusalFromTheSystemIsReported() {
        let system = FakeQuitSystem()
        system.holders[900] = slack
        system.answer = false
        #expect(service(system).quit(slack, force: false) == .failed)
    }
}
