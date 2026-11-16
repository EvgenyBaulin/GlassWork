import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

@MainActor
struct MenuBarFigureTests {
    @Test(arguments: [NumberStyle.compact, .precise])
    func memoryShareAndSwapFollowsNumberStyle(style: NumberStyle) {
        let sample = MemorySample(
            total: 32_000_000_000, app: 10_000_000_000, wired: 2_000_000_000, compressed: 0,
            cached: 0, free: 0, swapUsed: 1_500_000_000, swapTotal: 2_000_000_000, pressure: .warning
        )
        let options = [ItemOption.memoryFigure: MemoryFigure.shareAndSwap.rawValue, ItemOption.showsSwap: "false"]
        let item = ItemContent.memory(sample, style: style, options: options)
        let share = Format.percent(sample.usedShare, style: style)
        let swap = Format.bytes(Double(sample.swapUsed), style: style)
        #expect(item.figure == loc("\(share) · swap \(swap)"))
        #expect(item.alert == Palette.orange)
        #expect(item.metric == .memory)
        #expect(ItemContent.memory(nil, style: style, options: options).figure == "—")
    }

    @Test func zeroSwapIsStillShown() {
        let sample = MemorySample(
            total: 1000, app: 500, wired: 0, compressed: 0,
            cached: 0, free: 500, swapUsed: 0, swapTotal: 0, pressure: .normal
        )
        let item = ItemContent.memory(
            sample, style: .compact, options: [ItemOption.memoryFigure: MemoryFigure.shareAndSwap.rawValue]
        )
        #expect(item.figure == loc("\("50%") · swap \("0B")"))
        #expect(item.alert == nil)
    }

    @Test(arguments: [NumberStyle.compact, .precise])
    func diskShowsFreeShareAndKeepsTheLowSpaceWarning(style: NumberStyle) {
        var volume = DiskVolume(
            name: "Macintosh HD", path: "/", total: 1000, free: 250, isInternal: true, isEjectable: false
        )
        let options = [ItemOption.diskFigure: DiskFigure.freePercent.rawValue]
        let item = ItemContent.disk(volume, activity: nil, style: style, options: options)
        #expect(item.figure == Format.percent(0.25, style: style))
        #expect(item.alert == nil)
        volume.free = 50
        #expect(ItemContent.disk(volume, activity: nil, style: style, options: options).alert == Palette.orange)
        #expect(ItemContent.disk(nil, activity: nil, style: style, options: options).figure == "—")
    }

    @Test(arguments: NetworkDirection.allCases)
    func noActiveInterfaceIsOfflineForEveryDirection(direction: NetworkDirection) {
        let sample = NetworkSample(download: 0, upload: 0, interfaces: [], sessionReceived: 0, sessionSent: 0)
        let options = [ItemOption.networkDirection: direction.rawValue]
        let item = ItemContent.network(sample, style: .compact, options: options)
        #expect(item.figure == loc("Offline"))
        #expect(item.secondLine == nil)
        #expect(item.isDimmed)
        #expect(item.metric == nil)
    }

    @Test func anIdleInterfaceShowsZeroRates() {
        let counters = [InterfaceCounters(name: "en0", received: 100, sent: 10)]
        let sample = NetworkSample.between(counters, counters, seconds: 2)
        let item = ItemContent.network(sample, style: .compact, options: [:])
        #expect(item.figure == "↓ 0B/s")
        #expect(item.secondLine == "↑ 0B/s")
        #expect(!item.isDimmed)
    }

    @Test func aMissingNetworkSampleIsNotAnOfflineReport() {
        #expect(ItemContent.network(nil, style: .compact, options: [:]).figure == "—")
    }

    @Test func serverPortUsesTheSameFilteringAsTheCountAndDots() {
        let web = DevServer(port: 5173, pid: 1, process: "node", project: "web", kind: .web)
        let service = DevServer(port: 5432, pid: 2, process: "postgres", project: "db", kind: .service)
        let reading = DevServerReading.servers([web, service])
        #expect(ItemContent.devServers(reading).figure == "2")
        let item = ItemContent.devServers(reading, options: [ItemOption.countsServices: "false"])
        #expect(item.figure == ":5173")
        #expect(item.glyph == .dots(filled: 1, faint: 0))
        #expect(item.detail == ":5173 node")
        #expect(ItemContent.devServers(.servers([])).figure == "0")
        #expect(ItemContent.devServers(nil).figure == "—")
        #expect(ItemContent.devServers(.servers([])).template == item.template)
        #expect(ItemContent.devServers(nil).template == item.template)
    }

    @Test(arguments: ["", " \n\t\r\n "])
    func anEmptyNoteHasItsOwnDimmedFigure(note: String) {
        let item = ItemContent.notes(note)
        #expect(item.figure == loc("No note"))
        #expect(item.isDimmed)
        #expect(item.detail == nil)
    }

    @Test func aNoteShowsOnlyItsFirstLine() {
        let item = ItemContent.notes("  Ship the update  \r\nCheck the changelog")
        #expect(item.figure == "Ship the update")
        #expect(!item.isDimmed)
    }

    @Test func aLongNoteIsTruncatedByCharactersAndKeepsTheFullLineInTheTooltip() {
        let line = String(repeating: "👩🏽‍💻", count: 24)
        let item = ItemContent.notes(line + "\nSecond line")
        #expect(item.figure == String(repeating: "👩🏽‍💻", count: 19) + "…")
        #expect(item.figure.count == 20)
        #expect(item.detail == line)
        #expect(item.figureWidth == ItemContent.notes("").figureWidth)
    }

    @Test func notesReadTheExistingStore() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EverydayStore(store: SnapshotStore(directory: folder))
        store.update { $0.note = "Ship the update\nTomorrow" }
        let monitor = SystemMonitor(everyday: store)
        #expect(ItemContent.content(.notes, monitor: monitor, style: .compact).figure == "Ship the update")
    }
}
