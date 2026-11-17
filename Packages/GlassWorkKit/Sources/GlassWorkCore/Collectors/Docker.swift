import Foundation

public struct DockerContainer: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let image: String
    public let status: String
    public let isRunning: Bool
    /// Published ports, such as `5432→5432`.
    public let ports: [String]

    public init(id: String, name: String, image: String, status: String, isRunning: Bool, ports: [String]) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.isRunning = isRunning
        self.ports = ports
    }
}

public enum DockerReading: Codable, Sendable, Equatable {
    case notInstalled
    case notRunning
    case permissionDenied
    case failed(String)
    case containers([DockerContainer], context: String?)

    public var containers: [DockerContainer] {
        if case let .containers(containers, _) = self {
            return containers
        }
        return []
    }
}

/// One line of `docker ps --format json`. Only these fields are kept; labels and mounts are ignored.
private struct DockerLine: Decodable {
    let id: String
    let names: String
    let image: String
    let state: String
    let status: String
    let ports: String

    enum CodingKeys: String, CodingKey {
        case id = "ID", names = "Names", image = "Image", state = "State", status = "Status", ports = "Ports"
    }
}

public enum DockerParser {
    public static func containers(_ text: String) -> [DockerContainer] {
        let decoder = JSONDecoder()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let row = try? decoder.decode(DockerLine.self, from: Data(line.utf8)) else { return nil }
            return DockerContainer(
                id: row.id,
                name: row.names,
                image: row.image,
                status: row.status,
                isRunning: row.state == "running",
                ports: ports(row.ports)
            )
        }
    }

    /// Published ports once each, because Docker lists IPv4 and IPv6 separately.
    public static func ports(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: ", ").compactMap { entry in
            let sides = entry.components(separatedBy: "->")
            guard sides.count == 2, let host = sides[0].split(separator: ":").last else { return nil }
            let inner = sides[1].prefix { $0 != "/" }
            let isRange = host == inner && host.contains("-")
            let port = isRange ? String(host) : "\(host)→\(inner)"
            return seen.insert(port).inserted ? port : nil
        }
    }

    public static func reading(_ output: ProcessOutput, context: String? = nil) -> DockerReading {
        guard output.status != 0 else {
            return .containers(containers(output.stdout), context: context)
        }
        let errors = output.stderr
        if errors.localizedCaseInsensitiveContains("permission denied") {
            return .permissionDenied
        }
        if errors.contains("Cannot connect to the Docker daemon") || errors.contains("Is the docker daemon running") {
            return .notRunning
        }
        return .failed(errors.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
    }
}

/// One entry of `docker context ls --format json`.
public struct DockerContext: Sendable, Equatable, Identifiable {
    public let name: String
    public let isCurrent: Bool
    public let detail: String

    public var id: String {
        name
    }

    public init(name: String, isCurrent: Bool, detail: String = "") {
        self.name = name
        self.isCurrent = isCurrent
        self.detail = detail
    }
}

private struct DockerContextLine: Decodable {
    let name: String
    let current: Bool
    let description: String?
    let endpoint: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name", current = "Current", description = "Description", endpoint = "DockerEndpoint"
    }
}

public extension DockerParser {
    /// Lines of `docker context ls --format json`, in the order Docker lists them.
    static func contexts(_ text: String) -> [DockerContext] {
        let decoder = JSONDecoder()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let row = try? decoder.decode(DockerContextLine.self, from: Data(line.utf8)),
                  !row.name.isEmpty
            else { return nil }
            let detail = row.description.flatMap { $0.isEmpty ? nil : $0 } ?? row.endpoint ?? ""
            return DockerContext(name: row.name, isCurrent: row.current, detail: detail)
        }
    }
}

public enum DockerCLI {
    /// The binary picked in the panel when it is still there, otherwise the one found in the usual folders.
    public static func resolve(
        custom: String?,
        find: @Sendable () -> String? = { ToolLocator.find("docker") },
        check: ToolLocator.Check = ToolLocator.isExecutable
    ) -> String? {
        if let custom, !custom.isEmpty, check(custom) {
            return custom
        }
        return find()
    }
}

/// Reads containers and contexts. The only change it ever makes is `context use`, which the user asks for.
public struct DockerCollector: Sendable {
    private let runner: ProcessRunning
    private let locate: @Sendable () -> String?

    public init(runner: ProcessRunning, locate: @escaping @Sendable () -> String? = { ToolLocator.find("docker") }) {
        self.runner = runner
        self.locate = locate
    }

    public func read() async -> DockerReading {
        guard let docker = locate() else { return .notInstalled }
        let listing = ["ps", "-a", "--format", "json"]
        guard let output = try? await runner.run(docker, arguments: listing, timeout: 5) else {
            return .notRunning
        }
        let context = output.status == 0 ? await context(docker) : nil
        return DockerParser.reading(output, context: context)
    }

    public func contexts() async -> [DockerContext] {
        guard let docker = locate() else { return [] }
        let output = try? await runner.run(docker, arguments: ["context", "ls", "--format", "json"], timeout: 5)
        guard let output, output.status == 0 else { return [] }
        return DockerParser.contexts(output.stdout)
    }

    /// Makes `name` the current context. False when Docker refused or the name could be taken for an option.
    public func use(context name: String) async -> Bool {
        guard let docker = locate(), !name.isEmpty, !name.hasPrefix("-") else { return false }
        let output = try? await runner.run(docker, arguments: ["context", "use", name], timeout: 5)
        return output?.status == 0
    }

    private func context(_ docker: String) async -> String? {
        let output = try? await runner.run(docker, arguments: ["context", "show"], timeout: 3)
        let name = output?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }
}
