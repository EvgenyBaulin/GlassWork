import Foundation

/// A process that reports the Now Playing session. Tests substitute their own.
public protocol NowPlayingSource: AnyObject, Sendable {
    /// `onLine` and `onExit` arrive on a background queue.
    func start(onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws
    func send(_ line: String)
    func stop()
}

/// Keeps the adapter script running as a child process.
///
/// `ProcessRunner` runs a tool to its end, but the adapter stays up and takes commands.
/// Closing its input ends it, which also happens by itself if GlassWork crashes.
public final class NowPlayingAdapter: NowPlayingSource, @unchecked Sendable {
    // Why unchecked: the lock below guards `process`, `input` and `buffer`.
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = LineBuffer()
    private let executable: String
    private let arguments: [String]

    /// The script only needs the system's Perl, so nothing from the environment may change how that runs.
    private static let environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
    private static let stopGrace: TimeInterval = 2

    public convenience init(script: URL) {
        self.init(executable: "/usr/bin/perl", arguments: [script.path])
    }

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    deinit {
        stop()
    }

    public func start(
        onLine: @escaping @Sendable (String) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws {
        let child = Process()
        let output = Pipe()
        let commands = Pipe()
        child.executableURL = URL(filePath: executable)
        child.arguments = arguments
        child.environment = Self.environment
        child.standardInput = commands
        child.standardOutput = output
        // Nothing reads this, and a full pipe would block the script.
        child.standardError = FileHandle.nullDevice
        child.qualityOfService = .utility
        // A write after the script died must fail, not kill the app with SIGPIPE.
        _ = fcntl(commands.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let exit = ExitGate(onExit: onExit)
        // The closure holds `output` until the end of the stream: `Process` lets go of its pipes once the
        // child is gone, and a pipe that is freed closes its read end with the last lines still unread.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // End of the stream: nothing more can arrive, so the exit may be reported.
                handle.readabilityHandler = nil
                _ = output
                self?.flushRest(onLine)
                exit.streamEnded()
                return
            }
            guard let self else { return }
            let lines = lock.withLock { buffer.append(data) }
            lines.forEach(onLine)
        }
        child.terminationHandler = { [weak self] finished in
            self?.forget(finished)
            exit.processEnded(finished.terminationStatus)
        }
        try lock.withLock {
            buffer = LineBuffer()
            try child.run()
            process = child
            input = commands.fileHandleForWriting
        }
    }

    public func send(_ line: String) {
        let handle = lock.withLock { input }
        try? handle?.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Asks the script to finish and ends it if it does not.
    public func stop() {
        let (running, handle) = lock.withLock {
            defer {
                process = nil
                input = nil
            }
            return (process, input)
        }
        try? handle?.close()
        guard let running else { return }
        running.terminationHandler = nil
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.stopGrace) {
            if running.isRunning {
                running.terminate()
            }
        }
    }

    /// A last line that the script left without a newline.
    private func flushRest(_ onLine: @Sendable (String) -> Void) {
        lock.withLock { buffer.finish() }.forEach(onLine)
    }

    private func forget(_ finished: Process) {
        lock.withLock {
            guard process === finished else { return }
            process = nil
            try? input?.close()
            input = nil
        }
    }
}

/// Reports the exit once the child has ended and its output has been read to the end,
/// so `onExit` never overtakes the last lines.
private final class ExitGate: @unchecked Sendable {
    // Why unchecked: the lock guards every field.
    private let lock = NSLock()
    private var status: Int32?
    private var streamDone = false
    private var reported = false
    private let onExit: @Sendable (Int32) -> Void

    /// A grandchild that inherited the pipe could keep it open forever, so the wait for the end is bounded.
    private static let streamGrace: TimeInterval = 2

    init(onExit: @escaping @Sendable (Int32) -> Void) {
        self.onExit = onExit
    }

    func processEnded(_ value: Int32) {
        lock.withLock { status = value }
        report()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.streamGrace) { [self] in
            lock.withLock { streamDone = true }
            report()
        }
    }

    func streamEnded() {
        lock.withLock { streamDone = true }
        report()
    }

    private func report() {
        let value: Int32? = lock.withLock {
            guard !reported, streamDone, let status else { return nil }
            reported = true
            return status
        }
        if let value {
            onExit(value)
        }
    }
}
