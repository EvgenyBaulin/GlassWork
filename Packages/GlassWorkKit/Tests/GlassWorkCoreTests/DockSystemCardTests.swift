import Foundation
@testable import GlassWorkCore
import Testing

struct KeepAwakeCardStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func blocker(_ id: Int, pid: Int32, process: String, kind: SleepBlocker.Kind = .system) -> SleepBlocker {
        SleepBlocker(id: id, pid: pid, process: process, reason: "Reason \(id)", kind: kind)
    }

    @Test func offHasNoDeadlineAndNoDisplayLine() {
        let state = KeepAwakeCardState(isOn: false, ends: nil, keepsDisplayOn: true, blockers: [], at: now)
        #expect(state.status == .off)
        #expect(!state.isOn)
        #expect(state.keepsDisplayOn == nil)
    }

    @Test func onWithoutADeadlineRunsUntilOff() {
        let state = KeepAwakeCardState(isOn: true, ends: nil, keepsDisplayOn: false, blockers: [], at: now)
        #expect(state.status == .onUntilOff)
        #expect(state.keepsDisplayOn == false)
    }

    @Test func onWithAFutureDeadlineSaysUntilWhen() {
        let end = now.addingTimeInterval(900)
        let state = KeepAwakeCardState(isOn: true, ends: end, keepsDisplayOn: true, blockers: [], at: now)
        #expect(state.status == .until(end))
        #expect(state.isOn)
    }

    @Test func aDeadlineThatHasPassedIsNotShown() {
        let state = KeepAwakeCardState(
            isOn: true, ends: now.addingTimeInterval(-5), keepsDisplayOn: true, blockers: [], at: now
        )
        #expect(state.status == .onUntilOff)
    }

    @Test func othersKeepTheirOrderAndOnlyUsersCaffeinateCanBeStopped() {
        let blockers = [
            blocker(1, pid: 10, process: "caffeinate"),
            blocker(2, pid: 11, process: "caffeinate"),
            blocker(3, pid: 12, process: "zoom.us", kind: .display),
        ]
        let state = KeepAwakeCardState(
            isOn: false, ends: nil, keepsDisplayOn: true, blockers: blockers, stoppable: [10, 12], at: now
        )
        #expect(state.others.map(\.pid) == [10, 11, 12])
        #expect(state.others.map(\.canStop) == [true, false, false])
        #expect(state.others.map(\.keepsDisplayOn) == [false, false, true])
    }

    @Test func stoppableMeansACaffeinateOfThisUser() {
        let blockers = [
            blocker(1, pid: 10, process: "caffeinate"),
            blocker(2, pid: 11, process: "caffeinate"),
            blocker(3, pid: 12, process: "xcodebuild"),
        ]
        let facts: (Int32) -> CaffeinateStopper.ProcessFacts? = { pid in
            switch pid {
            case 10: CaffeinateStopper.ProcessFacts(name: "caffeinate", uid: 501)
            case 11: CaffeinateStopper.ProcessFacts(name: "caffeinate", uid: 0)
            default: CaffeinateStopper.ProcessFacts(name: "xcodebuild", uid: 501)
            }
        }
        // `canStop` compares with the real user, so use that user for the first.
        let own = getuid()
        let ownFacts: (Int32) -> CaffeinateStopper.ProcessFacts? = { pid in
            pid == 10 ? CaffeinateStopper.ProcessFacts(name: "caffeinate", uid: own) : facts(pid)
        }
        #expect(KeepAwakeCardState.stoppable(among: blockers, facts: ownFacts) == (own == 0 ? [10, 11] : [10]))
    }

    @Test func theThreeDurationsAreQuarterHourHourAndUntilOff() {
        #expect(KeepAwakeDuration.allCases.map(\.minutes) == [15, 60, nil])
    }
}

struct SoundAndCaptureTests {
    @Test func volumeReadsAsAPercentage() {
        #expect(SoundInfo(volume: 0.426).level == .percent(43))
        #expect(SoundInfo(volume: 1).level == .percent(100))
    }

    @Test func mutedOrZeroReadsAsMuted() {
        #expect(SoundInfo(volume: 0.5, isMuted: true).level == .muted)
        #expect(SoundInfo(volume: 0).level == .muted)
    }

    @Test func anOutputWithoutAVolumeIsUnknown() {
        #expect(SoundInfo(outputName: "HDMI").level == .unknown)
    }

    @Test func captureActivityFollowsWhatIsRunning() {
        #expect(CaptureStatus().activity == .idle)
        #expect(CaptureStatus(microphones: ["Built-in"]).activity == .microphone)
        #expect(CaptureStatus(cameras: ["FaceTime HD"]).activity == .camera)
        #expect(CaptureStatus(microphones: ["Built-in"], cameras: ["FaceTime HD"]).activity == .both)
    }
}

@MainActor
struct SystemMediaStoreTests {
    @MainActor
    final class FakeBackend: SystemMediaBackend {
        var reading = SystemMediaReading(sound: SoundInfo(outputName: "Speakers", volume: 0.5))
        var reads = 0
        var starts = 0
        var stops = 0
        var notify: (@MainActor () -> Void)?

        func read() -> SystemMediaReading {
            reads += 1
            return reading
        }

        func startListening(_ onChange: @escaping @MainActor () -> Void) {
            starts += 1
            notify = onChange
        }

        func stopListening() {
            stops += 1
            notify = nil
        }
    }

    @Test func nothingIsReadOrListenedToWithoutAHolder() {
        let backend = FakeBackend()
        let store = SystemMediaStore(backend: backend)
        #expect(store.reading == nil)
        #expect(backend.reads == 0 && backend.starts == 0)
        #expect(!store.isListening)
    }

    @Test func listeningStartsWithTheFirstHolderAndEndsWithTheLast() {
        let backend = FakeBackend()
        let store = SystemMediaStore(backend: backend)
        store.retain()
        store.retain()
        #expect(backend.starts == 1)
        #expect(store.reading?.sound.outputName == "Speakers")
        store.release()
        #expect(backend.stops == 0)
        store.release()
        #expect(backend.stops == 1)
        #expect(store.reading == nil)
        #expect(!store.isListening)
    }

    @Test func anEventReadsAgain() {
        let backend = FakeBackend()
        let store = SystemMediaStore(backend: backend)
        store.retain()
        backend.reading.capture = CaptureStatus(microphones: ["Built-in"])
        backend.notify?()
        #expect(store.reading?.capture.activity == .microphone)
    }

    @Test func releasingMoreThanRetainedChangesNothing() {
        let backend = FakeBackend()
        let store = SystemMediaStore(backend: backend)
        store.release()
        #expect(backend.stops == 0)
    }
}
