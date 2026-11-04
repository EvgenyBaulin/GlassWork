import Foundation

public struct ListeningSocket: Sendable, Equatable {
    public let pid: Int32
    public let command: String
    public let port: Int

    public init(pid: Int32, command: String, port: Int) {
        self.pid = pid
        self.command = command
        self.port = port
    }
}

public struct DevServer: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Speaks HTTP, so it can be opened in a browser.
        case web
        /// A database or similar: there is an address to copy but nothing to open.
        case service
    }

    public let port: Int
    public let pid: Int32
    public let process: String
    /// Well-known tool from the command line, such as `next dev`.
    public let tool: String?
    public let project: String
    public let kind: Kind
    public let uptime: TimeInterval?

    public init(
        port: Int,
        pid: Int32,
        process: String,
        tool: String? = nil,
        project: String,
        kind: Kind,
        uptime: TimeInterval? = nil
    ) {
        self.port = port
        self.pid = pid
        self.process = process
        self.tool = tool
        self.project = project
        self.kind = kind
        self.uptime = uptime
    }

    public var id: String {
        "\(pid):\(port)"
    }

    public var address: String {
        "localhost:\(port)"
    }

    public var url: URL? {
        kind == .web ? URL(string: "http://\(address)") : nil
    }

    /// What Copy puts on the clipboard.
    public var copyText: String {
        url?.absoluteString ?? address
    }
}

public enum DevServerReading: Sendable, Equatable {
    case servers([DevServer])
    case failed
}

public struct ProcessDetails: Sendable, Equatable {
    public let uptime: TimeInterval?
    public let tool: String?

    public init(uptime: TimeInterval?, tool: String?) {
        self.uptime = uptime
        self.tool = tool
    }
}

public enum DevServerParser {
    /// `lsof -F pcn`: one field per line, a process's fields follow its `p` line.
    public static func sockets(_ text: String) -> [ListeningSocket] {
        var result: [ListeningSocket] = []
        var seen = Set<String>()
        var pid: Int32?
        var command = ""
        for line in text.split(whereSeparator: \.isNewline) {
            let value = line.dropFirst()
            switch line.first {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = String(value)
            case "n":
                guard let pid, let port = value.split(separator: ":").last.flatMap({ Int($0) }),
                      seen.insert("\(pid):\(port)").inserted
                else { continue }
                result.append(ListeningSocket(pid: pid, command: command, port: port))
            default:
                continue
            }
        }
        return result
    }

    /// `lsof -a -d cwd -F pn`.
    public static func workingDirectories(_ text: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var pid: Int32?
        for line in text.split(whereSeparator: \.isNewline) {
            if line.first == "p" {
                pid = Int32(line.dropFirst())
            } else if line.first == "n", let pid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// `ps -o pid=,etime=,command=`. The command line can hold secrets, so nothing of it is kept
    /// except a match against the fixed list of tools.
    public static func processes(_ text: String) -> [Int32: ProcessDetails] {
        var result: [Int32: ProcessDetails] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]) else { continue }
            result[pid] = ProcessDetails(uptime: elapsed(String(fields[1])), tool: tool(in: String(fields[2])))
        }
        return result
    }

    /// `[[dd-]hh:]mm:ss`.
    public static func elapsed(_ text: String) -> TimeInterval? {
        let halves = text.split(separator: "-")
        let days = halves.count == 2 ? Double(halves[0]) : 0
        let clock = halves.last?.split(separator: ":").map { Double($0) } ?? []
        guard let days, !clock.isEmpty, clock.count <= 3, !clock.contains(nil) else { return nil }
        let seconds = clock.compactMap(\.self).reduce(0) { $0 * 60 + $1 }
        return days * 86400 + seconds
    }

    private static let tools: Set<String> = [
        "astro", "django", "flask", "gatsby", "gunicorn", "http.server", "hugo", "jekyll", "jupyter", "next",
        "nodemon", "nuxt", "parcel", "rails", "remix", "runserver", "storybook", "uvicorn", "vite", "webpack",
    ]
    private static let subcommands: Set<String> = ["dev", "serve", "start"]

    private static func tool(in command: String) -> String? {
        let words = command.split(separator: " ").map { $0.split(separator: "/").last.map(String.init) ?? "" }
        guard let index = words.firstIndex(where: tools.contains) else { return nil }
        let next = words.dropFirst(index + 1).first
        return next.map(subcommands.contains) == true ? "\(words[index]) \(next ?? "")" : words[index]
    }
}

public enum DevServerFilter {
    private static let services: Set<String> = [
        "clickhouse-server", "mariadbd", "memcached", "minio", "mongod", "mysqld", "postgres", "redis-server",
    ]
    private static let webServers: Set<String> = ["caddy", "httpd", "nginx"]
    private static let runtimes: Set<String> = [
        "beam.smp",
        "bun",
        "deno",
        "dotnet",
        "java",
        "node",
        "perl",
        "php",
        "ruby",
    ]

    /// Keeps what a developer started. Apps and daemons run from `/`, so a listening process counts
    /// when it is a known server, a language runtime working somewhere, or runs inside a project.
    public static func servers(
        sockets: [ListeningSocket],
        directories: [Int32: String],
        processes: [Int32: ProcessDetails],
        home: String
    ) -> [DevServer] {
        sockets.compactMap { socket in
            let directory = directories[socket.pid]
            let name = socket.command.lowercased()
            guard let kind = kind(of: name, directory: directory, home: home) else { return nil }
            let details = processes[socket.pid]
            return DevServer(
                port: socket.port,
                pid: socket.pid,
                process: name,
                tool: details?.tool,
                project: project(directory, home: home),
                kind: kind,
                uptime: details?.uptime
            )
        }
        .sorted { $0.port < $1.port }
    }

    private static func kind(of name: String, directory: String?, home: String) -> DevServer.Kind? {
        if services.contains(name) {
            return .service
        }
        if webServers.contains(name) {
            return .web
        }
        guard let directory, directory != "/" else { return nil }
        if runtimes.contains(name) || name.hasPrefix("python") {
            return .web
        }
        return directory.hasPrefix(home + "/") ? .web : nil
    }

    /// `~/Downloads` for a folder right in the home folder, the folder's name otherwise.
    static func project(_ directory: String?, home: String) -> String {
        guard let directory, directory != "/" else { return "" }
        let inside = directory.hasPrefix(home + "/") ? String(directory.dropFirst(home.count + 1)) : nil
        if let inside, !inside.contains("/") {
            return "~/\(inside)"
        }
        return URL(filePath: directory).lastPathComponent
    }
}

public struct DevServerCollector: Sendable {
    private let runner: ProcessRunning
    private let home: String

    public init(runner: ProcessRunning, home: String = NSHomeDirectory()) {
        self.runner = runner
        self.home = home
    }

    public func read() async -> DevServerReading {
        let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
        guard let listing = try? await runner.run("/usr/sbin/lsof", arguments: arguments, timeout: 5) else {
            return .failed
        }
        // lsof also exits with 1 when nothing listens, but stays silent on stderr then.
        guard listing.status == 0 || listing.stderr.isEmpty else { return .failed }
        let sockets = DevServerParser.sockets(listing.stdout)
        guard !sockets.isEmpty else { return .servers([]) }
        let pids = Set(sockets.map(\.pid)).sorted().map(String.init).joined(separator: ",")
        let directories = await output("/usr/sbin/lsof", ["-a", "-p", pids, "-d", "cwd", "-F", "pn"])
        let processes = await output("/bin/ps", ["-o", "pid=,etime=,command=", "-p", pids])
        return .servers(DevServerFilter.servers(
            sockets: sockets,
            directories: DevServerParser.workingDirectories(directories),
            processes: DevServerParser.processes(processes),
            home: home
        ))
    }

    private func output(_ tool: String, _ arguments: [String]) async -> String {
        await (try? runner.run(tool, arguments: arguments, timeout: 5))?.stdout ?? ""
    }
}
