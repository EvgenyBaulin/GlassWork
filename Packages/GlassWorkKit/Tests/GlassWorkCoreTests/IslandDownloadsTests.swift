import Foundation
@testable import GlassWorkCore
import Testing

struct IslandDownloadsTests {
    private let now = Date(timeIntervalSince1970: 1_794_850_000)

    private func file(_ name: String, downloading: Bool, progress: Double? = nil) -> DockFile {
        DockFile(
            path: "/Users/someone/Downloads/\(name)", name: name, added: now,
            isDownloading: downloading, progress: progress
        )
    }

    private func input(_ files: [DockFile]) -> IslandInput {
        var input = IslandInput()
        input.downloads = files
        return input
    }

    @Test func aDownloadInProgressShowsWithTheOnesThatJustFinished() throws {
        let previous = input([
            file("Assets.zip", downloading: true, progress: 0.4),
            file("Logo.svg", downloading: true),
        ])
        let current = input([
            file("Assets.zip", downloading: true, progress: 0.68),
            file("Logo.svg", downloading: false),
        ])

        let event = try #require(IslandEventBuilder.events(current: current, previous: previous, now: now).first)

        #expect(event.kind == .downloads)
        #expect(event.expires == nil)
        #expect(event.detail == .downloads([
            file("Assets.zip", downloading: true, progress: 0.68), file("Logo.svg", downloading: false),
        ]))
    }

    @Test func theLastOneFinishingShowsDoneForAMoment() throws {
        let previous = input([file("Assets.zip", downloading: true, progress: 0.9)])
        let current = input([file("Assets.zip", downloading: false)])

        let event = try #require(IslandEventBuilder.events(current: current, previous: previous, now: now).first)

        #expect(event.expires == now.addingTimeInterval(IslandEventBuilder.transientDuration))
        #expect(event.isTransition)
    }

    @Test func oldFilesShowNothing() {
        let files = [file("Old.pdf", downloading: false)]
        #expect(IslandEventBuilder.events(current: input(files), previous: input(files), now: now).isEmpty)
    }

    @MainActor
    @Test func theDoneMomentOutlivesTheNextReading() {
        let store = IslandStore()
        store.update(input: input([file("Assets.zip", downloading: true, progress: 0.9)]), now: now)
        store.update(input: input([file("Assets.zip", downloading: false)]), now: now.addingTimeInterval(2))
        store.update(input: input([file("Assets.zip", downloading: false)]), now: now.addingTimeInterval(4))

        #expect(store.queue.events.map(\.kind) == [.downloads])
    }
}
