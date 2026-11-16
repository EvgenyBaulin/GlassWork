import Foundation
@testable import GlassWorkCore
import Testing

struct SensorGroupOptionsTests {
    @Test func everyGroupShowsByDefault() {
        let options = SensorGroupOptions(options: [:])
        #expect(options.shownGroups == SensorGroup.allCases)
    }

    @Test func hidingAGroupStoresItAndShowingRemovesIt() {
        var stored: [String: String] = [:]
        SensorGroupOptions.set(.gpu, isShown: false, in: &stored)
        SensorGroupOptions.set(.storage, isShown: false, in: &stored)
        let options = SensorGroupOptions(options: stored)
        #expect(!options.shows(.gpu))
        #expect(!options.shows(.storage))
        #expect(options.shows(.battery))
        SensorGroupOptions.set(.gpu, isShown: true, in: &stored)
        SensorGroupOptions.set(.storage, isShown: true, in: &stored)
        #expect(stored.isEmpty)
    }

    @Test func theOlderOtherSwitchStillHidesOther() {
        let options = SensorGroupOptions(options: [ItemOption.showsUnknownSensors: "false"])
        #expect(!options.shows(.other))
        #expect(options.shows(.gpu))
    }

    @Test func otherIsStoredInItsOwnFlag() {
        var stored: [String: String] = [:]
        SensorGroupOptions.set(.other, isShown: false, in: &stored)
        #expect(stored == [ItemOption.showsUnknownSensors: "false"])
        SensorGroupOptions.set(.other, isShown: true, in: &stored)
        #expect(stored.isEmpty)
    }

    @Test func anUnknownGroupNameIsIgnored() {
        let options = SensorGroupOptions(options: [ItemOption.hiddenSensorGroups: "gpu,flux"])
        #expect(!options.shows(.gpu))
        #expect(options.shows(.battery))
    }
}
