import Foundation
@testable import GlassWorkCore
import Testing

struct IslandLevelsTests {
    private let now = Date(timeIntervalSince1970: 1_794_850_000)

    private func input(_ levels: SystemLevels?) -> IslandInput {
        var input = IslandInput()
        input.levels = levels
        return input
    }

    @Test func aVolumeChangeShowsForAMoment() throws {
        let events = IslandEventBuilder.events(
            current: input(SystemLevels(volume: 0.62, outputName: "Speakers", brightness: 0.7)),
            previous: input(SystemLevels(volume: 0.5, outputName: "Speakers", brightness: 0.7)),
            now: now
        )
        let event = try #require(events.first { $0.kind == .volume })
        #expect(event.expires == now.addingTimeInterval(IslandEventBuilder.transientDuration))
        guard case let .levels(levels, changed) = event.detail else {
            Issue.record("not a levels event")
            return
        }
        #expect(changed == .volume)
        #expect(levels.volume == 0.62)
    }

    @Test func muteCountsAsAVolumeChange() {
        #expect(IslandEventBuilder.levelChange(
            SystemLevels(volume: 0.5, isMuted: true), SystemLevels(volume: 0.5, isMuted: false)
        ) == .volume)
    }

    @Test func aBrightnessChangeLeadsWithBrightness() {
        #expect(IslandEventBuilder.levelChange(
            SystemLevels(volume: 0.5, brightness: 0.3), SystemLevels(volume: 0.5, brightness: 0.6)
        ) == .brightness)
    }

    @Test func nothingChangedOrNoEarlierReadingShowsNothing() {
        let same = SystemLevels(volume: 0.5, brightness: 0.6)
        #expect(IslandEventBuilder.levelChange(same, same) == nil)
        #expect(IslandEventBuilder.levelChange(same, nil) == nil)
        #expect(IslandEventBuilder.events(current: input(same), previous: nil, now: now).isEmpty)
    }

    @Test func anOutputWithoutVolumeShowsNoVolume() {
        #expect(IslandEventBuilder.levelChange(SystemLevels(volume: nil), SystemLevels(volume: 0.4)) == nil)
    }
}
