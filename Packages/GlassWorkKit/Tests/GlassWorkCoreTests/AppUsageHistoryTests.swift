import Foundation
@testable import GlassWorkCore
import Testing

private let id = "com.example.app"
private let start = Date(timeIntervalSince1970: 1_800_000_000 / 600 * 600)

private func app(cpu: Double, memory: UInt64 = 1_000_000, named name: String = id) -> AppUsage {
    AppUsage(id: name, pid: 1, name: name, cpu: cpu, memory: memory)
}

private func minutes(_ value: Double) -> Date {
    start.addingTimeInterval(value * 60)
}

struct AppUsageHistoryTests {
    @Test
    func readsInOneMinuteAverage() {
        var history = AppUsageHistory()
        history.record([app(cpu: 10)], at: minutes(0))
        history.record([app(cpu: 30)], at: start.addingTimeInterval(30))
        history.record([app(cpu: 99)], at: minutes(1))
        let points = history.points(for: id, since: start)
        #expect(points.count == 1)
        #expect(points.first?.cpu == 20)
        #expect(points.first?.date == start)
    }

    @Test
    func theCurrentMinuteWaitsForItsEnd() {
        var history = AppUsageHistory()
        history.record([app(cpu: 10)], at: minutes(0))
        #expect(history.points(for: id, since: start).isEmpty)
    }

    @Test
    func tenMinutesMakeOneRecord() throws {
        var history = AppUsageHistory()
        var records: [AppUsageRecord] = []
        for minute in 0 ... 11 {
            if let record = history.record([app(cpu: Double(minute))], at: minutes(Double(minute))) {
                records.append(record)
            }
        }
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.time == Int(start.timeIntervalSince1970))
        #expect(record.apps[id]?.first == 4.5)
    }

    @Test
    func olderThanAnHourKeepsOnlyTheCoarsePoints() {
        var history = AppUsageHistory()
        for minute in 0 ... 130 {
            history.record([app(cpu: 1)], at: minutes(Double(minute)))
        }
        let all = history.points(for: id, since: start)
        let fine = all.filter { $0.date >= minutes(70) }
        let coarse = all.filter { $0.date < minutes(69) }
        #expect(fine.count >= 59)
        #expect(coarse.count <= 7)
    }

    @Test
    func coarseAndFinePointsNeverRepeatADate() {
        var history = AppUsageHistory()
        for minute in 0 ... 90 {
            history.record([app(cpu: 1)], at: minutes(Double(minute)))
        }
        let dates = history.points(for: id, since: start).map(\.date)
        #expect(Set(dates).count == dates.count)
        #expect(dates == dates.sorted())
    }

    @Test
    func aWeekIsAllThatStays() throws {
        var history = AppUsageHistory()
        history.restore([AppUsageRecord(time: Int(start.timeIntervalSince1970), apps: [id: [1, 2]])], now: start)
        #expect(history.points(for: id, since: .distantPast).count == 1)
        let later = start.addingTimeInterval(AppUsageHistory.retention + 3600)
        history.restore([AppUsageRecord(time: Int(later.timeIntervalSince1970), apps: [id: [3, 4]])], now: later)
        let points = history.points(for: id, since: .distantPast)
        #expect(points.count == 1)
        #expect(try #require(points.first).cpu == 3)
    }

    @Test
    func anAppGoneForAWeekIsForgotten() {
        var history = AppUsageHistory()
        history.restore([AppUsageRecord(time: Int(start.timeIntervalSince1970), apps: ["old": [1, 2]])], now: start)
        let later = start.addingTimeInterval(AppUsageHistory.retention + 3600)
        history.restore([], now: later)
        #expect(history.points(for: "old", since: .distantPast).isEmpty)
    }

    @Test
    func theNewerRecordOfAMomentWins() throws {
        var history = AppUsageHistory()
        let time = Int(start.timeIntervalSince1970)
        history.restore(
            [AppUsageRecord(time: time, apps: [id: [1, 1]]), AppUsageRecord(time: time, apps: [id: [2, 2]])],
            now: start
        )
        let points = history.points(for: id, since: .distantPast)
        #expect(points.count == 1)
        #expect(try #require(points.first).cpu == 2)
    }

    @Test
    func aRecordWithTheWrongShapeIsSkipped() {
        var history = AppUsageHistory()
        history.restore([AppUsageRecord(time: Int(start.timeIntervalSince1970), apps: [id: [1]])], now: start)
        #expect(history.points(for: id, since: .distantPast).isEmpty)
    }

    @Test
    func whatIsNotSavedYetCanBeWrittenOnQuit() throws {
        var history = AppUsageHistory()
        history.record([app(cpu: 10)], at: minutes(0))
        history.record([app(cpu: 20)], at: minutes(1))
        let record = try #require(history.pending())
        #expect(record.time == Int(start.timeIntervalSince1970))
        #expect(record.apps[id]?.first == 15)
    }

    @Test
    func nothingToSaveIsNothing() {
        #expect(AppUsageHistory().pending() == nil)
    }

    @Test
    func thinningAveragesNeighbours() {
        let points = (0 ..< 1000).map { AppUsagePoint(date: minutes(Double($0)), cpu: 10, memory: 5) }
        let thin = AppUsageHistory.thinned(points, limit: 300)
        #expect(thin.count <= 300)
        #expect(thin.allSatisfy { $0.cpu == 10 })
        #expect(thin.first?.date == start)
    }

    @Test
    func aShortStretchIsNotThinned() {
        let points = [AppUsagePoint(date: start, cpu: 1, memory: 1)]
        #expect(AppUsageHistory.thinned(points, limit: 10) == points)
    }

    @Test
    func aPointDoesNotLoseTheFigureOnScreen() {
        let point = AppUsagePoint(date: start, cpu: 24.5, memory: 6_200_000_000)
        #expect(abs(point.memory - 6_200_000_000) < 1000)
        #expect(point.cpu == 24.5)
    }
}

struct AppUsageLogTests {
    private func temporaryLog() -> AppUsageLog {
        AppUsageLog(url: FileManager.default.temporaryDirectory
            .appending(path: "glasswork-apps-\(UUID().uuidString)/AppUsage.jsonl"))
    }

    @Test
    func keepsWhatIsAppended() throws {
        let log = temporaryLog()
        let first = AppUsageRecord(time: Int(start.timeIntervalSince1970), apps: [id: [1.5, 2]])
        let second = AppUsageRecord(time: first.time + 600, apps: [id: [3, 4]])
        try log.append(first)
        try log.append(second)
        #expect(log.load(now: start) == [first, second])
    }

    @Test
    func aMissingFileIsAnEmptyHistory() {
        #expect(temporaryLog().load(now: start).isEmpty)
    }

    @Test
    func garbageLinesAreSkipped() {
        let text = """
        {"t":1800000000,"a":{"x":[1,2]}}
        not json at all
        {"t":1800000600,"a":{"x":[3,4
        {"t":1800001200,"a":{"x":[5,6]}}
        """
        #expect(AppUsageLog.decode(text).map(\.time) == [1_800_000_000, 1_800_001_200])
    }

    @Test
    func binaryRubbishDoesNotCrashALoad() throws {
        let log = temporaryLog()
        try FileManager.default.createDirectory(
            at: log.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xFF, 0xFE, 0x00, 0xC3, 0x28]).write(to: log.url)
        #expect(log.load(now: start).isEmpty)
    }

    @Test
    func expiredLinesLeaveTheFile() throws {
        let log = temporaryLog()
        let old = AppUsageRecord(time: Int(start.timeIntervalSince1970), apps: [id: [1, 2]])
        let later = start.addingTimeInterval(AppUsageHistory.retention + 3600)
        let new = AppUsageRecord(time: Int(later.timeIntervalSince1970), apps: [id: [3, 4]])
        try log.append(old)
        try log.append(new)
        #expect(log.load(now: later) == [new])
        let text = try String(contentsOf: log.url, encoding: .utf8)
        #expect(AppUsageLog.decode(text) == [new])
    }
}

@MainActor
struct AppUsageStoreTests {
    private func temporaryStore() -> AppUsageStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "glasswork-store-\(UUID().uuidString).jsonl")
        return AppUsageStore(reader: AppUsageReader(table: EmptyTable()), log: AppUsageLog(url: url))
    }

    @Test
    func anAppThatQuitLeavesTheListAtOnce() {
        let store = temporaryStore()
        store.show([app(cpu: 1)])
        store.running = [RunningAppInfo(pid: 5, name: "Other", bundleID: nil, path: nil, role: .regular)]
        #expect(store.apps.isEmpty)
    }

    @Test
    func nothingIsReadWithoutApps() {
        let store = temporaryStore()
        store.tick(at: start, isLive: true)
        #expect(store.apps.isEmpty)
    }

    @Test
    func theBackgroundPaceIsTheLowOne() {
        #expect(AppUsageStore.backgroundInterval >= 60)
        #expect(AppUsageStore.liveInterval < AppUsageStore.backgroundInterval)
    }
}

private struct EmptyTable: ProcessTable {
    func pids() -> [Int32] {
        []
    }

    func counters(of _: Int32) -> ProcessCounters? {
        nil
    }

    func facts(of pid: Int32) -> ProcessFacts {
        ProcessFacts(pid: pid, parent: 1, responsible: pid, path: nil)
    }
}
