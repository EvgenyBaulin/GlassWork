import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// The Calendar, To-Dos, Timers and Colours panels in the states added with loading, counts, Undo and Done.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct AgendaEverydayPanelSnapshotTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [true, false])
    func calendarLoadsBeforeShowingEvents(dark: Bool) {
        let view = CalendarAgenda(access: .granted, isLoaded: false, today: [], tomorrow: nil, request: {})
            .padding(14)
            .frame(width: 320)
        snapshotPanel(view, name: "calendar-loading", dark: dark)
    }

    @Test(arguments: [true, false])
    func calendarSaysNoEventsOnceLoaded(dark: Bool) {
        let view = CalendarAgenda(access: .granted, isLoaded: true, today: [], tomorrow: nil, request: {})
            .padding(14)
            .frame(width: 320)
        snapshotPanel(view, name: "calendar-empty", dark: dark)
    }

    @Test(arguments: [true, false])
    func todoFiltersShowCountsAndUndoToast(dark: Bool) {
        let view = VStack(spacing: 10) {
            TodoFilterPicker(
                filter: .constant(.today),
                counts: [.all: 12, .today: 3, .overdue: 0, .flagged: 1]
            )
            UndoToast(message: loc("Completed"), undo: {})
        }
        .padding(14)
        .frame(width: 320)
        snapshotPanel(view, name: "todos-counts-undo", dark: dark)
    }

    @Test(arguments: [true, false])
    func timersListFinishedOnesWithDismiss(dark: Bool) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EverydayStore(store: SnapshotStore(directory: folder))
        store.update { data in
            // Paused, so the time left does not move with the clock.
            var running = CountdownTimer(title: "10 min", duration: 600, start: start)
            running.togglePause(at: start.addingTimeInterval(120))
            data.timers = [running]
            data.finishedTimers = [FinishedTimer(
                CountdownTimer(title: "Tea", duration: 180, start: start),
                finishedAt: start.addingTimeInterval(180)
            )]
        }
        let view = TimersPanel(monitor: SystemMonitor(everyday: store))
            .frame(width: 340)
        snapshotPanel(view, name: "timers-finished", dark: dark)
    }

    @Test(arguments: [true, false])
    func coloursOfferTheFormats(dark: Bool) {
        let view = ColourFormatPicker(format: .swiftUI, select: { _ in })
            .padding(14)
            .frame(width: 320)
        snapshotPanel(view, name: "colours-format", dark: dark)
    }
}
