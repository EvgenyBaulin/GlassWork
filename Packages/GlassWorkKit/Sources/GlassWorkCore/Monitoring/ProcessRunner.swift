import Foundation

/// Runs external tools. Tests substitute their own implementation.
public protocol ProcessRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput
}

public struct ProcessOutput: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ProcessRunnerError: Error, Equatable {
    case notFound(String)
    case timedOut(String)
}

/// `Foundation.Process` wrapper with a hard timeout.
public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunnerError.notFound(executable)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try Self.execute(executable, arguments: arguments, timeout: timeout)
                })
            }
        }
    }

    private static func execute(_ path: String, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput {
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let killer = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let timedOut = killer.isCancelled == false && process.terminationReason == .uncaughtSignal
        killer.cancel()
        if timedOut {
            throw ProcessRunnerError.timedOut(path)
        }
        return ProcessOutput(
            status: process.terminationStatus,
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self)
        )
    }
}
