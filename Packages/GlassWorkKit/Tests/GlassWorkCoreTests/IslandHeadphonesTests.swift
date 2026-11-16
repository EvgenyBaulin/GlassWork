import Foundation
@testable import GlassWorkCore
import Testing

struct IslandHeadphonesTests {
    private let now = Date(timeIntervalSince1970: 1_794_850_000)
    private let buds = DeviceBattery(name: "Someone's AirPods Pro", kind: .headphones, charge: 0.8)
    private let budsCase = DeviceBattery(name: "Someone's AirPods Pro Case", kind: .headphones, charge: 0.74)
    private let mouse = DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.5)

    private func input(output: String, volume: Double = 0.5) -> IslandInput {
        var input = IslandInput()
        input.levels = SystemLevels(volume: volume, outputName: output)
        input.deviceBatteries = [buds, budsCase, mouse]
        return input
    }

    @Test func switchingToAirPodsShowsTheirBatteries() throws {
        let events = IslandEventBuilder.events(
            current: input(output: "Someone's AirPods Pro", volume: 0.3),
            previous: input(output: "MacBook Pro Speakers"),
            now: now
        )
        #expect(events.map(\.kind) == [.airPods])
        let event = try #require(events.first)
        #expect(event.detail == .headphones(name: "Someone's AirPods Pro", batteries: [buds, budsCase]))
    }

    @Test func otherOutputsShowNothing() {
        let events = IslandEventBuilder.events(
            current: input(output: "Studio Display Speakers"),
            previous: input(output: "MacBook Pro Speakers"),
            now: now
        )
        #expect(events.isEmpty)
    }

    @Test func headphonesWithoutAKnownBatteryStillShow() {
        var current = input(output: "Beats Studio")
        current.deviceBatteries = []
        let detail = IslandEventBuilder.headphones(current, previous: input(output: "MacBook Pro Speakers"))
        #expect(detail == .headphones(name: "Beats Studio", batteries: []))
    }
}
