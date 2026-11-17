import Foundation
@testable import GlassWorkCore
import Testing

struct DockFolderEditingTests {
    private let apps = ["A", "B", "C", "D"].map { DockApp(path: "/Applications/\($0).app", name: $0) }

    private func folder(_ apps: [DockApp], sort: FolderSort = .manual) -> AppFolder {
        var folder = AppFolder(name: "Work", apps: apps)
        folder.sort = sort
        return folder
    }

    private func inside(_ id: UUID, _ items: [DockItem]) -> AppFolder? {
        items.compactMap { item -> AppFolder? in
            if case let .folder(folder) = item, folder.id == id {
                return folder
            }
            return nil
        }.first
    }

    @Test func aFolderWrittenBeforeIconsExistStillDecodes() throws {
        let json = Data(#"{"name":"Old","apps":[],"sort":"name"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppFolder.self, from: json)
        #expect(decoded.name == "Old")
        #expect(decoded.emoji == nil)
        #expect(decoded.tint == nil)
        #expect(decoded.sort == .name)
    }

    @Test func anUnknownColourIsDroppedButTheFolderStays() throws {
        let json = Data(#"{"name":"New","apps":[],"tint":"chartreuse","emoji":"🚀"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppFolder.self, from: json)
        #expect(decoded.tint == nil)
        #expect(decoded.emoji == "🚀")
    }

    @Test func theIconSurvivesEncoding() throws {
        var made = folder(apps)
        made.tint = .teal
        made.emoji = "🎮"
        made.symbol = "star.fill"
        let back = try JSONDecoder().decode(AppFolder.self, from: JSONEncoder().encode(made))
        #expect(back == made)
    }

    @Test func settingTheIconKeepsOneEmojiCharacter() throws {
        let made = folder(apps)
        let result = DockLayout.setIcon(
            folder: made.id,
            symbol: "star.fill",
            emoji: "🚀🚀",
            tint: .red,
            in: [.folder(made)]
        )
        let changed = try #require(inside(made.id, result))
        #expect(changed.emoji == "🚀")
        #expect(changed.symbol == "star.fill")
        #expect(changed.tint == .red)
        let cleared = DockLayout.setIcon(folder: made.id, symbol: nil, emoji: "", tint: nil, in: result)
        #expect(inside(made.id, cleared)?.emoji == nil)
    }

    @Test func movingOntoAnotherTakesItsPlace() {
        #expect(DockLayout.moving(apps[0], onto: apps[2], in: apps) == [apps[1], apps[2], apps[0], apps[3]])
        #expect(DockLayout.moving(apps[3], onto: apps[1], in: apps) == [apps[0], apps[3], apps[1], apps[2]])
        #expect(DockLayout.moving(apps[0], onto: nil, in: apps) == [apps[1], apps[2], apps[3], apps[0]])
        #expect(DockLayout.moving(apps[1], onto: apps[1], in: apps) == apps)
    }

    @Test func movingByOneStopsAtTheEnds() {
        #expect(DockLayout.moving(apps[1], by: 1, in: apps) == [apps[0], apps[2], apps[1], apps[3]])
        #expect(DockLayout.moving(apps[0], by: -1, in: apps) == apps)
        #expect(DockLayout.moving(apps[3], by: 1, in: apps) == apps)
    }

    @Test func reorderingAFolderBecomesManualFromTheOrderOnShow() throws {
        let made = folder([apps[2], apps[0], apps[1]], sort: .name)
        // Shown by name: A, B, C. Moving C onto A puts it first.
        let result = DockLayout.reorder(apps[2], onto: apps[0], inFolder: made.id, in: [.folder(made)])
        let changed = try #require(inside(made.id, result))
        #expect(changed.sort == .manual)
        #expect(changed.apps == [apps[2], apps[0], apps[1]])
        let second = DockLayout.reorder(apps[0], onto: apps[1], inFolder: made.id, in: result)
        #expect(inside(made.id, second)?.apps == [apps[2], apps[1], apps[0]])
    }

    @Test func draggingAnAppOutPutsItBackInTheDock() {
        let made = folder([apps[0], apps[1], apps[2]])
        let items: [DockItem] = [.folder(made), .app(apps[3])]
        let result = DockLayout.moveOut(apps[1], ofFolder: made.id, in: items)
        #expect(result.count == 3)
        #expect(result[1] == .app(apps[1]))
        #expect(inside(made.id, result)?.apps == [apps[0], apps[2]])
    }

    @Test func draggingOutInFrontOfAnItemPlacesItThere() {
        let made = folder([apps[0], apps[1], apps[2]])
        let items: [DockItem] = [.app(apps[3]), .folder(made)]
        let result = DockLayout.moveOut(apps[1], ofFolder: made.id, before: .app(apps[3]), in: items)
        #expect(result.first == .app(apps[1]))
        #expect(result.count == 3)
    }

    @Test func draggingOutOfAPairDissolvesTheFolder() {
        let made = folder([apps[0], apps[1]])
        let result = DockLayout.moveOut(apps[0], ofFolder: made.id, in: [.folder(made)])
        #expect(result == [.app(apps[0]), .app(apps[1])])
    }

    @Test func anAppAlreadyInTheDockIsNotDuplicated() {
        let made = folder([apps[0], apps[1], apps[2]])
        let items: [DockItem] = [.folder(made), .app(apps[1])]
        #expect(DockLayout.moveOut(apps[1], ofFolder: made.id, in: items) == items)
    }

    @Test func dragPayloadsRoundTrip() {
        let id = UUID()
        let plain = DockDrag.parse(DockDrag.payload(path: "/Applications/A.app"))
        #expect(plain.path == "/Applications/A.app")
        #expect(plain.folder == nil)
        let fromFolder = DockDrag.parse(DockDrag.payload(path: "/Applications/A: B.app", fromFolder: id))
        #expect(fromFolder.path == "/Applications/A: B.app")
        #expect(fromFolder.folder == id)
    }
}
