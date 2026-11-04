import Foundation
@testable import GlassWorkCore
import Testing

struct TemperatureUnitTests {
    @Test
    func celsiusStaysAsItIs() {
        #expect(Format.temperature(47, unit: .celsius).hasPrefix("47"))
    }

    @Test
    func fahrenheitIsConverted() {
        #expect(Format.temperature(100, unit: .fahrenheit).hasPrefix("212"))
        #expect(Format.temperature(0, unit: .fahrenheit).hasPrefix("32"))
    }

    @Test
    func anExplicitUnitIsWrittenOut() {
        #expect(Format.temperature(47, unit: .celsius).hasSuffix("C"))
        #expect(Format.temperature(47, unit: .fahrenheit).hasSuffix("F"))
    }

    @Test
    func anOldSnapshotWithoutAUnitStillReads() throws {
        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000))
        snapshot.temperatureUnit = .fahrenheit
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded.temperatureUnit == .fahrenheit)
    }
}

struct PingOptionTests {
    private func settings(_ options: [String: String]) -> AppSettings {
        var settings = AppSettings()
        settings.update(.ping) { $0.options = options }
        return settings
    }

    @Test
    func theDefaultsMatchTheModule() {
        let options = DeveloperOptions(settings: AppSettings())
        #expect(options.pingIntervalSeconds == 30)
        #expect(options.pingTimeoutSeconds == 2)
    }

    @Test
    func aHandEditCannotPingWithoutPause() {
        let options = DeveloperOptions(settings: settings([
            DeveloperOptions.Key.pingInterval: "0",
            DeveloperOptions.Key.pingTimeout: "9999",
        ]))
        #expect(options.pingIntervalSeconds == 5)
        #expect(options.pingTimeoutSeconds == 10)
    }

    @Test
    func theTimeoutReachesPing() {
        let arguments = PingCollector.arguments(host: "1.1.1.1", timeoutSeconds: 5)
        #expect(arguments == ["-n", "-c", "1", "-t", "5", "--", "1.1.1.1"])
    }

    @Test(arguments: [(10, 180), (30, 60), (60, 30)])
    func theLogKeepsHalfAnHourAtAnyPace(seconds: Int, samples: Int) {
        var log = PingLog()
        log.follow(intervalSeconds: seconds)
        for index in 0 ..< 300 {
            log.append(.timeout, at: Date(timeIntervalSince1970: Double(index)))
        }
        #expect(log.samples.count == samples)
    }

    @Test
    func aSlowerPaceDropsTheOldestSamples() {
        var log = PingLog()
        log.follow(intervalSeconds: 10)
        for index in 0 ..< 100 {
            log.append(.timeout, at: Date(timeIntervalSince1970: Double(index)))
        }
        log.follow(intervalSeconds: 60)
        #expect(log.samples.count == 30)
        #expect(log.samples.last?.date == Date(timeIntervalSince1970: 99))
    }
}

struct NetworkInterfaceChoiceTests {
    private let sample = NetworkSample(
        download: 300,
        upload: 30,
        interfaces: [
            .init(name: "en0", download: 200, upload: 20),
            .init(name: "en5", download: 100, upload: 10),
        ],
        sessionReceived: 1000,
        sessionSent: 500
    )

    @Test
    func nothingChosenKeepsTheSum() {
        #expect(sample.only(nil) == sample)
    }

    @Test
    func oneInterfaceShowsOnlyItsSpeed() {
        let chosen = sample.only("en5")
        #expect(chosen.download == 100)
        #expect(chosen.upload == 10)
        #expect(chosen.interfaces.map(\.name) == ["en5"])
    }

    /// An interface with no traffic is not in the sample at all, and it must read as idle, not as the sum.
    @Test
    func aQuietInterfaceReadsAsZero() {
        let chosen = sample.only("en9")
        #expect(chosen.download == 0)
        #expect(chosen.upload == 0)
        #expect(chosen.interfaces.isEmpty)
    }

    @Test
    func theSessionTotalsStay() {
        #expect(sample.only("en5").sessionReceived == 1000)
    }
}

struct HardwareOrderTests {
    private func volume(_ path: String) -> DiskVolume {
        DiskVolume(name: path, path: path, total: 100, free: 50, isInternal: true, isEjectable: false)
    }

    @Test
    func theChosenVolumeGoesFirst() {
        let volumes = [volume("/"), volume("/Volumes/Data"), volume("/Volumes/Backup")]
        let ordered = volumes.startingWith("/Volumes/Backup")
        #expect(ordered.map(\.path) == ["/Volumes/Backup", "/", "/Volumes/Data"])
    }

    @Test
    func noChoiceKeepsTheStartupDiskFirst() {
        let volumes = [volume("/"), volume("/Volumes/Data")]
        #expect(volumes.startingWith(nil) == volumes)
    }

    @Test
    func aDiskThatIsGoneChangesNothing() {
        let volumes = [volume("/"), volume("/Volumes/Data")]
        #expect(volumes.startingWith("/Volumes/Gone") == volumes)
    }
}
