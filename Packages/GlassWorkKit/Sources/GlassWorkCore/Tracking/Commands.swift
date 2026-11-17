import Foundation

/// The user's own command, run at a click from a widget.
public struct UserCommand: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var command: String
    public var directory: String?
    public var timeout: TimeInterval = 300
    /// Destructive commands ask first; a stray click on a widget must not run them.
    public var asksFirst = false

    public init(name: String, command: String) {
        self.name = name
        self.command = command
    }
}

public struct CommandResult: Codable, Sendable, Equatable {
    public var status: Int32
    public var duration: TimeInterval
    public var tail: String
    public var finishedAt: Date

    /// Last lines of output, enough to see why a command failed.
    public static func tail(of output: String, lines: Int = 4) -> String {
        output.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }
}

public enum CommandRunner {
    public static func run(
        _ command: UserCommand,
        using runner: ProcessRunning = ProcessRunner()
    ) async -> CommandResult {
        let start = Date()
        // Quoting stops the shell from expanding `~`, so it is done here.
        let folder = command.directory.map { NSString(string: $0).expandingTildeInPath }
        let script = folder.map { "cd \(quoted($0)) && \(command.command)" } ?? command.command
        let output = try? await runner.run("/bin/zsh", arguments: ["-lc", script], timeout: command.timeout)
        return CommandResult(
            status: output?.status ?? -1,
            duration: Date().timeIntervalSince(start),
            tail: CommandResult.tail(of: (output?.stdout ?? "") + (output?.stderr ?? "")),
            finishedAt: Date()
        )
    }

    static func quoted(_ path: String) -> String {
        "'" + path.replacing("'", with: "'\\''") + "'"
    }
}

public enum EndpointMethod: String, Codable, Sendable, CaseIterable {
    case get = "GET"
    case head = "HEAD"
}

/// A site or API to watch.
public struct Endpoint: Codable, Sendable, Equatable, Identifiable {
    public static let intervalRange: ClosedRange<TimeInterval> = 10 ... 3600
    public static let timeoutRange: ClosedRange<TimeInterval> = 1 ... 60

    public var id = UUID()
    public var url: URL
    public var interval: TimeInterval = 60
    public var expectedStatus = 200
    public var method = EndpointMethod.get
    public var timeout: TimeInterval = 10

    public init(url: URL) {
        self.url = url
    }

    /// Endpoints saved before the method and timeout existed keep working with the old fixed values.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try values.decode(URL.self, forKey: .url)
        interval = try values.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 60
        expectedStatus = try values.decodeIfPresent(Int.self, forKey: .expectedStatus) ?? 200
        method = (try? values.decodeIfPresent(EndpointMethod.self, forKey: .method)) ?? .get
        timeout = try values.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 10
    }

    /// Whether the last check is older than the interval, so a heartbeat does not hit every site every time.
    public func isDue(lastCheck: Date?, at date: Date) -> Bool {
        guard let lastCheck else { return true }
        return date.timeIntervalSince(lastCheck) >= interval - 5
    }
}

public struct EndpointCheck: Codable, Sendable, Equatable {
    public var date: Date
    public var status: Int?
    public var milliseconds: Double?

    public func isUp(expected: Int) -> Bool {
        status == expected
    }
}

public enum EndpointChecker {
    public static func check(_ endpoint: Endpoint, session: URLSession = .shared) async -> EndpointCheck {
        let start = Date()
        var request = URLRequest(
            url: endpoint.url,
            timeoutInterval: min(
                max(endpoint.timeout, Endpoint.timeoutRange.lowerBound),
                Endpoint.timeoutRange.upperBound
            )
        )
        request.httpMethod = endpoint.method.rawValue
        guard let (_, response) = try? await session.data(for: request) else {
            return EndpointCheck(date: start, status: nil, milliseconds: nil)
        }
        return EndpointCheck(
            date: start,
            status: (response as? HTTPURLResponse)?.statusCode,
            milliseconds: Date().timeIntervalSince(start) * 1000
        )
    }
}
