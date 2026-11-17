import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
struct ColourItemTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store() -> EverydayStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return EverydayStore(store: SnapshotStore(directory: folder))
    }

    @Test func noColoursShowsADash() {
        let item = ItemContent.colours(store(), at: now)
        #expect(item.figure == "—")
        #expect(item.swatch == nil)
        #expect(item.isDimmed)
    }

    @Test func theLastColourIsTheSwatchAndTheText() {
        let colours = store()
        colours.update { $0.addColor("#112233") }
        colours.update { $0.addColor("#AABBCC") }
        let item = ItemContent.colours(colours, at: now)
        #expect(item.figure == "#AABBCC")
        #expect(item.swatch != nil)
    }

    @Test func copyingSaysCopiedForAMoment() {
        let colours = store()
        colours.update { $0.addColor("#AABBCC") }
        colours.noteColourCopied(at: now)
        #expect(ItemContent.colours(colours, at: now.addingTimeInterval(1)).figure == loc("Copied"))
        #expect(ItemContent.colours(colours, at: now.addingTimeInterval(4)).figure == "#AABBCC")
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct ColourItemSnapshotTests {
    private func snapshot(_ content: ItemContent, name: String, dark: Bool) throws {
        let renderer = MenuBarItemRenderer(
            module: .colours,
            style: .figure,
            numbers: .compact,
            monitor: SystemMonitor()
        )
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        renderer.appearance = appearance
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textWidth = ceil((content.template as NSString).size(withAttributes: [.font: font]).width)
        let size = CGSize(width: textWidth + 28, height: 24)
        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = try #require(renderer.image(content: content, size: size))
        view.appearance = appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: view, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
        }
    }

    @Test(arguments: [true, false])
    func lastColourAndCopied(dark: Bool) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let colours = EverydayStore(store: SnapshotStore(directory: folder))
        colours.update { $0.addColor("#6B5BB5") }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try snapshot(ItemContent.colours(colours, at: now), name: "colours-last", dark: dark)
        colours.noteColourCopied(at: now)
        try snapshot(ItemContent.colours(colours, at: now), name: "colours-copied", dark: dark)
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct TodoGroupSnapshotTests {
    @Test(arguments: [true, false])
    func groupsShowTheListColourAndPriorityMarks(dark: Bool) {
        let work = "#E5484D"
        let home = "#30A46C"
        let view = VStack(alignment: .leading, spacing: 8) {
            TodoGroupHeader(name: "Work", color: work)
            TodoRow(item: TodoItem(
                id: "1",
                title: "Send the report",
                listName: "Work",
                listColor: work,
                priority: 1
            )) {}
            TodoRow(item: TodoItem(
                id: "2",
                title: "Review the plan",
                listName: "Work",
                listColor: work,
                priority: 5
            )) {}
            TodoGroupHeader(name: "Home", color: home)
            TodoRow(item: TodoItem(
                id: "3",
                title: "Water the plants",
                listName: "Home",
                listColor: home,
                priority: 9
            )) {}
            TodoRow(item: TodoItem(id: "4", title: "Call the bank", listName: "Home", listColor: home)) {}
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        snapshotPanel(view, name: "todos-groups-priority", dark: dark)
    }

    @Test(arguments: [true, false])
    func listChoicesShowEveryListWithItsColour(dark: Bool) {
        let lists = [
            CalendarChoice(id: "work", title: "Work", account: "iCloud", color: "#E5484D"),
            CalendarChoice(id: "home", title: "Home", account: "iCloud", color: "#30A46C"),
        ]
        let view = Form {
            TodoListChoices(
                access: .granted,
                lists: lists,
                options: TodoOptions(options: [ItemOption.hiddenTodoLists: "home"]),
                change: { _, _ in }
            )
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 160)
        snapshotPanel(view, name: "todos-list-choices", dark: dark)
    }
}
