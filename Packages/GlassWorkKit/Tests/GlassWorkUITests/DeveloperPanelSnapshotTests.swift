import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Draws a panel the way the app does, at its natural height.
@MainActor
func snapshotPanel(
    _ view: some View,
    name: String,
    dark: Bool = true,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let scheme: ColorScheme = dark ? .dark : .light
    let root = view
        .environment(\.colorScheme, scheme)
        .background(dark ? Color(white: 0.12) : Color(white: 0.96))
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
    withSnapshotTesting(record: record ? .all : .missing) {
        assertSnapshot(
            of: host,
            as: .image(precision: 0.98),
            named: name + (dark ? "-dark" : "-light"),
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DeveloperPanelSnapshotTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func pingLog(_ values: [Double?]) -> PingLog {
        var log = PingLog()
        for (index, value) in values.enumerated() {
            let outcome: PingOutcome = value.map { .reply(milliseconds: $0) } ?? .timeout
            log.append(outcome, at: start.addingTimeInterval(Double(index) * 30))
        }
        return log
    }

    @Test(arguments: [true, false])
    func ping(dark: Bool) {
        let values: [Double?] = [14, 16, 15, 18, 46, 19, 15, 14, 17, nil, 16, 18, 15, 22, 16, 14]
        snapshotPanel(PingPanel(log: pingLog(values), host: "1.1.1.1"), name: "ping", dark: dark)
    }

    @Test func pingHostDown() {
        snapshotPanel(PingPanel(log: pingLog([14, 15, nil, nil, nil]), host: "10.0.0.9"), name: "ping-down")
    }
}

@MainActor
struct DeveloperItemTests {
    @Test func pingTurnsRedOnlyWhenTheHostIsDown() {
        var log = PingLog()
        log.append(.reply(milliseconds: 18.4), at: Date())
        #expect(ItemContent.ping(log).figure == "18 ms")
        #expect(ItemContent.ping(log).alert == nil)

        for _ in 0 ..< 3 {
            log.append(.timeout, at: Date())
        }
        #expect(ItemContent.ping(log).alert == Palette.red)
    }

    @Test func offlineIsFaintNotRed() {
        var log = PingLog()
        for _ in 0 ..< 3 {
            log.append(.offline, at: Date())
        }
        let item = ItemContent.ping(log)

        #expect(item.alert == nil)
        #expect(item.isFaint)
    }

    @Test func pingGraphShowsTheWholeLogNotTheLastMinute() {
        var log = PingLog()
        for index in 0 ..< 40 {
            log.append(.reply(milliseconds: Double(index)), at: Date())
        }
        #expect(ItemContent.ping(log).values?.count == 40)
    }
}
