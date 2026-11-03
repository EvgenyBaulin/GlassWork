import Foundation

public struct ProcessUsage: Codable, Sendable, Equatable, Identifiable {
    public var id: Int32 {
        pid
    }

    public var pid: Int32
    public var name: String
    /// Percent of one core.
    public var cpu: Double
    public var memory: UInt64

    public init(pid: Int32, name: String, cpu: Double, memory: UInt64) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.memory = memory
    }
}

public enum ProcessList {
    public static let arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]

    /// Parses `ps -Aceo pid=,pcpu=,rss=,comm=`. Names may contain spaces.
    public static func parse(_ output: String) -> [ProcessUsage] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1].replacing(",", with: ".")),
                  let kilobytes = UInt64(fields[2])
            else { return nil }
            return ProcessUsage(pid: pid, name: String(fields[3]), cpu: cpu, memory: kilobytes * 1024)
        }
    }

    public static func read(using runner: ProcessRunning = ProcessRunner()) async -> [ProcessUsage] {
        guard let output = try? await runner.run("/bin/ps", arguments: arguments, timeout: 3) else { return [] }
        return parse(output.stdout)
    }
}
