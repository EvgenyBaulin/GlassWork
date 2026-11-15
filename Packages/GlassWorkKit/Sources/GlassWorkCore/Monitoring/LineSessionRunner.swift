import Foundation

/// Talks to a tool that reads requests on stdin and answers line by line, such as a JSON-RPC server.
public protocol LineSessionRunning: Sendable {
    /// Sends `lines` and returns the first stdout line for which `isAnswer` is true. Stdin stays open until
    /// then: some servers quit on end of input without answering.
    func exchange(
        _ executable: String,
        arguments: [String],
        send lines: [String],
        until isAnswer: @escaping @Sendable (String) -> Bool,
        timeout: TimeInterval
    ) async throws -> String
}

public struct LineSessionRunner: LineSessionRunning {
    public init() {}

    public func exchange(
        _ executable: String,
        arguments: [String],
        send lines: [String],
        until isAnswer: @escaping @Sendable (String) -> Bool,
        timeout: TimeInterval
    ) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunnerError.notFound(executable)
        }
        let session = Session(executable: executable, arguments: arguments, isAnswer: isAnswer)
        return try await withCheckedThrowingContinuation { continuation in
            session.start(sending: lines, timeout: timeout, continuation: continuation)
        }
    }
}

/// One child process and the single answer it owes.
/// Why unchecked: every mutable field is read and written under `lock`; the pipes' handlers and the timer run
/// on their own queues and meet only there.
private final class Session: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let executable: String
    private let isAnswer: @Sendable (String) -> Bool
    private var buffer = Data()
    private var continuation: CheckedContinuation<String, Error>?

    init(executable: String, arguments: [String], isAnswer: @escaping @Sendable (String) -> Bool) {
        self.executable = executable
        self.isAnswer = isAnswer
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    func start(sending lines: [String], timeout: TimeInterval, continuation: CheckedContinuation<String, Error>) {
        lock.withLock { self.continuation = continuation }
        // Drained so a chatty child can never block on a full stderr pipe.
        errors.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
        output.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty {
                finish(.failure(ProcessRunnerError.endedWithoutAnswer(executable)))
            } else {
                received(data)
            }
        }
        process.terminationHandler = { [self] _ in
            // Lines still in the pipe come first; the empty read above ends the session if none matched.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
                finish(.failure(ProcessRunnerError.endedWithoutAnswer(executable)))
            }
        }
        do {
            try process.run()
        } catch {
            finish(.failure(error))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
            finish(.failure(ProcessRunnerError.timedOut(executable)))
        }
        // A child that quits early must cost an error, not a SIGPIPE that would end GlassWork.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let payload = lines.map { $0 + "\n" }.joined()
        try? input.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
    }

    private func received(_ data: Data) {
        let complete: [String] = lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: buffer[buffer.startIndex ..< newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex ... newline)
            }
            return lines
        }
        if let answer = complete.first(where: isAnswer) {
            finish(.success(answer))
        }
    }

    /// The first outcome wins; the child is stopped and nothing is left running.
    private func finish(_ result: Result<String, Error>) {
        let waiting: CheckedContinuation<String, Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        guard let waiting else { return }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
        waiting.resume(with: result)
    }
}
