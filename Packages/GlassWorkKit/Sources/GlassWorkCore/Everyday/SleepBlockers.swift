import Darwin
import Foundation
import IOKit.pwr_mgt

/// A program that keeps the Mac, or its display, from sleeping: a `caffeinate`, a video call, a build.
public struct SleepBlocker: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// The Mac stays awake; the display may sleep.
        case system
        /// The display stays on, and with it the Mac.
        case display
    }

    public var id: Int
    public var pid: Int32
    public var process: String
    /// What the program calls its reason, such as `Xcode running tests.`
    public var reason: String
    public var kind: Kind
    public var started: Date?
    /// When it lets go by itself, as with `caffeinate -t`.
    public var ends: Date?
    /// It holds on while this process lives, as with `caffeinate -w` or `caffeinate some-command`.
    public var whileProcess: Int32?

    public init(
        id: Int,
        pid: Int32,
        process: String,
        reason: String,
        kind: Kind,
        started: Date? = nil,
        ends: Date? = nil,
        whileProcess: Int32? = nil
    ) {
        self.id = id
        self.pid = pid
        self.process = process
        self.reason = reason
        self.kind = kind
        self.started = started
        self.ends = ends
        self.whileProcess = whileProcess
    }

    public var isCaffeinate: Bool {
        process == "caffeinate"
    }
}

public enum SleepBlockers {
    private static let systemTypes: Set = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]
    private static let displayTypes: Set = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
    /// powerd itself holds the Mac awake while the display is on; that is macOS, not a program.
    private static let ignoredProcesses: Set = ["powerd"]

    /// Turns what `IOPMCopyAssertionsByProcess` returns into blockers, oldest first. Background tasks, network
    /// wakes and the like are left out, and so is `ownPID`: GlassWork shows its own Keep Awake apart.
    public static func parse(_ byProcess: [Int32: [[String: Any]]], ownPID: Int32) -> [SleepBlocker] {
        byProcess.flatMap { pid, assertions in
            assertions.compactMap { blocker($0, pid: pid) }
        }
        .filter { $0.pid != ownPID && !ignoredProcesses.contains($0.process) }
        .sorted { ($0.started ?? .distantPast, $0.id) < ($1.started ?? .distantPast, $1.id) }
    }

    private static func blocker(_ assertion: [String: Any], pid: Int32) -> SleepBlocker? {
        let type = assertion["AssertType"] as? String ?? ""
        let kind: SleepBlocker.Kind
        if systemTypes.contains(type) {
            kind = .system
        } else if displayTypes.contains(type) {
            kind = .display
        } else {
            return nil
        }
        guard (assertion["AssertLevel"] as? Int ?? 255) > 0 else { return nil }
        let id = assertion["GlobalUniqueID"] as? Int ?? assertion["AssertionId"] as? Int ?? Int(pid)
        let timeout = (assertion["TimeoutSeconds"] as? Double).flatMap { $0 > 0 ? $0 : nil }
        let updated = assertion["AssertTimeoutUpdateTime"] as? Date ?? assertion["AssertStartWhen"] as? Date
        return SleepBlocker(
            id: id,
            pid: (assertion["AssertPID"] as? Int).map(Int32.init) ?? pid,
            process: assertion["Process Name"] as? String ?? "",
            reason: assertion["AssertName"] as? String ?? "",
            kind: kind,
            started: assertion["AssertStartWhen"] as? Date,
            ends: timeout.flatMap { seconds in updated.map { $0.addingTimeInterval(seconds) } },
            whileProcess: (assertion["AssertionOnBehalfOfPID"] as? Int).map(Int32.init)
                ?? onBehalfOf(assertion["Details"] as? String)
        )
    }

    /// `caffeinate some-command` says so only in its details: `… on behalf of '/usr/bin/perl' (pid 93380)`.
    static func onBehalfOf(_ details: String?) -> Int32? {
        guard let details, let match = details.firstMatch(of: /\(pid (\d+)\)/) else { return nil }
        return Int32(match.1)
    }

    /// Every blocker on this Mac now.
    public static func read(ownPID: Int32 = getpid()) -> [SleepBlocker] {
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
              let dictionary = result?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        var byProcess: [Int32: [[String: Any]]] = [:]
        for (pid, assertions) in dictionary {
            byProcess[pid.int32Value] = assertions
        }
        return parse(byProcess, ownPID: ownPID)
    }
}

/// Stops a `caffeinate` of this user. Anything else, or anyone else's, stays as it is.
public enum CaffeinateStopper {
    public struct ProcessFacts: Sendable, Equatable {
        public var name: String
        public var uid: uid_t

        public init(name: String, uid: uid_t) {
            self.name = name
            self.uid = uid
        }
    }

    public static func canStop(_ facts: ProcessFacts?, as user: uid_t = getuid()) -> Bool {
        facts?.name == "caffeinate" && facts?.uid == user
    }

    /// Looks again right before the signal: the pid may have been reused by another program since the list was read.
    @discardableResult
    public static func stop(_ pid: Int32) -> Bool {
        guard canStop(facts(of: pid)) else { return false }
        return kill(pid, SIGTERM) == 0
    }

    public static func facts(of pid: Int32) -> ProcessFacts? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let text = { (raw: UnsafeRawBufferPointer) in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        let name = withUnsafeBytes(of: info.pbi_name, text)
        return ProcessFacts(name: name.isEmpty ? withUnsafeBytes(of: info.pbi_comm, text) : name, uid: info.pbi_uid)
    }
}
