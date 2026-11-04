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

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else {
                handle.readabilityHandler = nil
                return
            }
            let lines = lock.withLock { buffer.append(data) }
            lines.forEach(onLine)
        }
        child.terminationHandler = { [weak self] finished in
            self?.forget(finished)
            onExit(finished.terminationStatus)
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

    private func forget(_ finished: Process) {
        lock.withLock {
            guard process === finished else { return }
            process = nil
            try? input?.close()
            input = nil
        }
    }
}
