import Foundation
@testable import GlassWorkCore
import Testing

struct EjectOptionTests {
    private func volume(
        _ name: String,
        ejectable: Bool = true,
        image: Bool? = false,
        network: Bool? = false
    ) -> DiskVolume {
        DiskVolume(
            name: name,
            path: "/Volumes/\(name)",
            total: 100,
            free: 50,
            isInternal: false,
            isEjectable: ejectable,
            isDiskImage: image,
            isNetwork: network
        )
    }

    @Test
    func aDriveCanBeEjected() {
        #expect(EjectOptions().allows(volume("Backup")))
    }

    @Test
    func theStartupDiskCannot() {
        #expect(!EjectOptions().allows(volume("Macintosh HD", ejectable: false)))
    }

    @Test
    func diskImagesFollowTheirSwitch() {
        let image = volume("Installer", image: true)
        #expect(EjectOptions().allows(image))
        #expect(!EjectOptions(options: [ItemOption.ejectIncludesImages: "false"]).allows(image))
    }

    @Test
    func networkVolumesStayOutUntilAskedFor() {
        let share = volume("Share", ejectable: false, network: true)
        #expect(!EjectOptions().allows(share))
        #expect(EjectOptions(options: [ItemOption.ejectIncludesNetwork: "true"]).allows(share))
    }

    @Test
    func theNeverListWinsWhateverTheCase() {
        let options = EjectOptions(options: [ItemOption.ejectNever: "Time Machine, backup"])
        #expect(!options.allows(volume("Backup")))
        #expect(!options.allows(volume("time machine")))
        #expect(options.allows(volume("Photos")))
    }

    @Test
    func aVolumeFromAnOldSnapshotCountsAsAPlainDrive() {
        #expect(EjectOptions().allows(volume("Backup", image: nil, network: nil)))
    }

    @Test
    func emptyEntriesInTheListMeanNothing() {
        #expect(EjectOptions.names(" , ,") == [])
        #expect(EjectOptions.names(nil) == [])
    }
}

struct DevServerRuleTests {
    private func server(_ port: Int, _ process: String = "node") -> DevServer {
        DevServer(port: port, pid: 1, process: process, project: "site", kind: .web)
    }

    @Test
    func noRuleKeepsEverything() {
        #expect(DevServerRule().keeps(server(80)))
    }

    @Test
    func theRangeIsInclusive() {
        let rule = DevServerRule(range: "3000-9999", ignored: nil)
        #expect(rule.keeps(server(3000)))
        #expect(rule.keeps(server(9999)))
        #expect(!rule.keeps(server(2999)))
        #expect(!rule.keeps(server(10000)))
    }

    @Test(arguments: ["3000", "9999-3000", "from here", "", "1-2-3"])
    func aRangeThatMakesNoSenseIsIgnored(text: String) {
        #expect(DevServerRule(range: text, ignored: nil).ports == nil)
    }

    @Test
    func aTypedDashStillCounts() {
        #expect(DevServerRule(range: "3000 – 4000", ignored: nil).ports == 3000 ... 4000)
    }

    @Test
    func portsAndNamesCanBeIgnored() {
        let rule = DevServerRule(range: nil, ignored: ":5432, 6379 Postgres")
        #expect(!rule.keeps(server(5432)))
        #expect(!rule.keeps(server(6379)))
        #expect(!rule.keeps(server(7000, "postgres")))
        #expect(rule.keeps(server(7000)))
    }

    @Test
    func aFailedReadStaysFailed() {
        #expect(DevServerReading.failed.filtered(by: DevServerRule()) == .failed)
    }

    @Test
    func theReadingKeepsOnlyWhatTheRuleAllows() {
        let reading = DevServerReading.servers([server(3000), server(80)])
        let rule = DevServerRule(range: "3000-4000", ignored: nil)
        #expect(reading.filtered(by: rule).servers.map(\.port) == [3000])
    }

    @Test
    func aHandEditCannotReadWithoutPause() {
        var settings = AppSettings()
        settings.update(.devServers) { $0.options[DeveloperOptions.Key.devServerSeconds] = "0" }
        #expect(DeveloperOptions(settings: settings).devServerSeconds == 5)
    }
}
