import Foundation

/// An app's use at one moment. Small on purpose: a week of many apps stays in memory.
public struct AppUsagePoint: Sendable, Equatable {
    private let minute: Int32
    private let cpuValue: Float
    private let memoryValue: Float

    public init(date: Date, cpu: Double, memory: Double) {
        minute = Int32(date.timeIntervalSince1970 / 60)
        cpuValue = Float(cpu)
        memoryValue = Float(memory)
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(minute) * 60)
    }

    /// Percent of one core.
    public var cpu: Double {
        Double(cpuValue)
    }

    /// Bytes.
    public var memory: Double {
        Double(memoryValue)
    }

    fileprivate var time: Int32 {
        minute
    }
}

/// Ten minutes of every app, as one line of the history file.
public struct AppUsageRecord: Codable, Sendable, Equatable {
    /// Seconds since 1970 at the start of the ten minutes.
    public var time: Int
    /// `[cpu, memory]` by app id.
    public var apps: [String: [Double]]

    public init(time: Int, apps: [String: [Double]]) {
        self.time = time
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey {
        case time = "t"
        case apps = "a"
    }
}

/// The last week of every app: each minute of the last hour, and every ten minutes before that.
public struct AppUsageHistory: Sendable {
    public static let retention: TimeInterval = 7 * 86400
    private static let recentSpan: TimeInterval = 3600
    private static let minute = 60
    private static let longStep = 600

    private var recent: [String: [AppUsagePoint]] = [:]
    private var long: [String: [AppUsagePoint]] = [:]
    private var minuteBucket: UsageBucket?
    private var longBucket: UsageBucket?

    public init() {}

    /// Adds one read. Reads falling in the same minute are averaged, so the pace of reading does not matter.
    ///
    /// - Returns: The ten minutes that just ended, for the history file.
    @discardableResult
    public mutating func record(_ apps: [AppUsage], at date: Date) -> AppUsageRecord? {
        let index = Int(date.timeIntervalSince1970) / Self.minute
        var finished: AppUsageRecord?
        if let bucket = minuteBucket, bucket.index != index {
            finished = closeMinute(bucket, now: date)
            minuteBucket = nil
        }
        var bucket = minuteBucket ?? UsageBucket(index: index)
        for app in apps {
            bucket.add(app.id, cpu: app.cpu, memory: Double(app.memory))
        }
        minuteBucket = bucket
        return finished
    }

    private mutating func closeMinute(_ bucket: UsageBucket, now: Date) -> AppUsageRecord? {
        let date = Date(timeIntervalSince1970: Double(bucket.index * Self.minute))
        for (id, sum) in bucket.sums {
            Self.append(AppUsagePoint(date: date, cpu: sum.cpu, memory: sum.memory), to: &recent, id: id)
        }
        pruneRecent(now: now)
        let tenth = bucket.index * Self.minute / Self.longStep
        var finished: AppUsageRecord?
        if let longBucket, longBucket.index != tenth {
            finished = closeLong(longBucket, now: now)
            self.longBucket = nil
        }
        var long = longBucket ?? UsageBucket(index: tenth)
        for (id, sum) in bucket.sums {
            long.add(id, cpu: sum.cpu, memory: sum.memory)
        }
        longBucket = long
        return finished
    }

    private mutating func closeLong(_ bucket: UsageBucket, now: Date) -> AppUsageRecord {
        let record = bucket.record(step: Self.longStep)
        add(record)
        prune(now: now)
        return record
    }

    /// What has not reached the file yet, for quitting. The next launch starts a fresh ten minutes.
    public func pending() -> AppUsageRecord? {
        var bucket = longBucket
        if let minuteBucket {
            let tenth = minuteBucket.index * Self.minute / Self.longStep
            var combined = bucket?.index == tenth ? bucket ?? UsageBucket(index: tenth) : UsageBucket(index: tenth)
            for (id, sum) in minuteBucket.sums {
                combined.add(id, cpu: sum.cpu, memory: sum.memory)
            }
            bucket = combined
        }
        return bucket?.record(step: Self.longStep)
    }

    /// Puts back what the file holds.
    public mutating func restore(_ records: [AppUsageRecord], now: Date) {
        for record in records.sorted(by: { $0.time < $1.time }) {
            add(record)
        }
        prune(now: now)
    }

    private mutating func add(_ record: AppUsageRecord) {
        let date = Date(timeIntervalSince1970: Double(record.time))
        for (id, values) in record.apps where values.count == 2 {
            Self.append(AppUsagePoint(date: date, cpu: values[0], memory: values[1]), to: &long, id: id)
        }
    }

    /// A chart keys points by date, so a moment appears once. The newer value wins: a launch inside the same ten
    /// minutes as the last quit writes that stretch again.
    private static func append(_ point: AppUsagePoint, to series: inout [String: [AppUsagePoint]], id: String) {
        if let last = series[id]?.last, last.time >= point.time {
            if last.time == point.time {
                series[id]?.removeLast()
                series[id]?.append(point)
            }
            return
        }
        series[id, default: []].append(point)
    }

    private mutating func pruneRecent(now: Date) {
        let oldest = now.addingTimeInterval(-Self.recentSpan)
        for id in recent.keys {
            recent[id]?.removeAll { $0.date < oldest }
            if recent[id]?.isEmpty == true {
                recent[id] = nil
            }
        }
    }

    private mutating func prune(now: Date) {
        let oldest = now.addingTimeInterval(-Self.retention)
        for id in long.keys {
            long[id]?.removeAll { $0.date < oldest }
            if long[id]?.isEmpty == true {
                long[id] = nil
            }
        }
    }

    /// Everything since `date`, oldest first: the coarse points, then the fine ones where those begin.
    public func points(for id: String, since date: Date) -> [AppUsagePoint] {
        let fine = recent[id] ?? []
        let end = fine.first?.date ?? .distantFuture
        let coarse = (long[id] ?? []).filter { $0.date >= date && $0.date < end }
        return coarse + fine.filter { $0.date >= date }
    }

    /// Thins a long stretch to at most `limit` points by averaging neighbours. A chart cannot show more than its
    /// width anyway, and it redraws on every move of the pointer.
    public static func thinned(_ points: [AppUsagePoint], limit: Int) -> [AppUsagePoint] {
        guard limit > 0, points.count > limit else { return points }
        let size = (points.count + limit - 1) / limit
        return stride(from: 0, to: points.count, by: size).map { start in
            let group = points[start ..< min(start + size, points.count)]
            let count = Double(group.count)
            return AppUsagePoint(
                date: group[group.startIndex].date,
                cpu: group.reduce(0) { $0 + $1.cpu } / count,
                memory: group.reduce(0) { $0 + $1.memory } / count
            )
        }
    }
}

/// Averages of several reads, per app.
private struct UsageBucket: Sendable {
    struct Sum: Sendable {
        var cpuTotal = 0.0
        var memoryTotal = 0.0
        var count = 0.0

        var cpu: Double {
            cpuTotal / max(count, 1)
        }

        var memory: Double {
            memoryTotal / max(count, 1)
        }
    }

    let index: Int
    var sums: [String: Sum] = [:]

    mutating func add(_ id: String, cpu: Double, memory: Double) {
        sums[id, default: Sum()].cpuTotal += cpu
        sums[id, default: Sum()].memoryTotal += memory
        sums[id, default: Sum()].count += 1
    }

    func record(step: Int) -> AppUsageRecord {
        AppUsageRecord(
            time: index * step,
            apps: sums.mapValues { [($0.cpu * 100).rounded() / 100, $0.memory.rounded()] }
        )
    }
}

/// The history file: one JSON line per ten minutes, so saving adds a line instead of rewriting a week.
public struct AppUsageLog: Sendable {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GlassWork/AppUsage.jsonl")
    }

    public init(url: URL = AppUsageLog.defaultURL) {
        self.url = url
    }

    /// A line that cannot be read is skipped: a crash can leave half a line, and the rest still counts.
    public static func decode(_ text: String) -> [AppUsageRecord] {
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(AppUsageRecord.self, from: Data(line.utf8))
        }
    }

    public func append(_ record: AppUsageRecord) throws {
        var line = try JSONEncoder().encode(record)
        line.append(UInt8(ascii: "\n"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            try line.write(to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Reads the file and drops what is past the week from it.
    public func load(now: Date) -> [AppUsageRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let all = Self.decode(text)
        let oldest = now.addingTimeInterval(-AppUsageHistory.retention).timeIntervalSince1970
        let kept = all.filter { Double($0.time) >= oldest }
        if kept.count != all.count {
            rewrite(kept)
        }
        return kept
    }

    private func rewrite(_ records: [AppUsageRecord]) {
        let encoder = JSONEncoder()
        let lines = records.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
