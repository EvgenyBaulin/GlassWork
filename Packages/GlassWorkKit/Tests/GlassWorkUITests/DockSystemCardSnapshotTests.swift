import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// The Keep Awake, Sound and Mic & Camera cards and tiles of the Dock, in both themes. They are built from fixed
/// values, so nothing here asks Core Audio, CoreMediaIO or the power manager.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockSystemCardSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let utc = TimeZone(identifier: "UTC") ?? .gmt

    private func awake(isOn: Bool, ends: Date?, others: Bool) -> KeepAwakeCardState {
        let blockers = others ? [
            SleepBlocker(id: 1, pid: 10, process: "caffeinate", reason: "caffeinate command-line tool", kind: .system),
            SleepBlocker(id: 2, pid: 11, process: "zoom.us", reason: "Zoom meeting", kind: .display),
        ] : []
        return KeepAwakeCardState(
            isOn: isOn, ends: ends, keepsDisplayOn: true, blockers: blockers, stoppable: [10], at: now
        )
    }

    private func card(_ state: KeepAwakeCardState) -> some View {
        DockKeepAwakeCardContent(state: state, locale: Locale(identifier: "en_US"), timeZone: utc)
    }

    @Test(arguments: [true, false])
    func keepAwakeOffWithOthers(dark: Bool) {
        assertPanel(card(awake(isOn: false, ends: nil, others: true)), dark: dark, name: "dock-keepawake-off")
    }

    @Test(arguments: [true, false])
    func keepAwakeOnUntil(dark: Bool) {
        assertPanel(
            card(awake(isOn: true, ends: now.addingTimeInterval(3600), others: false)),
            dark: dark, name: "dock-keepawake-until"
        )
    }

    @Test(arguments: [true, false])
    func keepAwakeOnUntilOff(dark: Bool) {
        assertPanel(card(awake(isOn: true, ends: nil, others: true)), dark: dark, name: "dock-keepawake-on")
    }

    @Test(arguments: [true, false])
    func soundCard(dark: Bool) {
        let info = SoundInfo(outputName: "MacBook Pro Speakers", volume: 0.62, inputName: "MacBook Pro Microphone")
        assertPanel(DockSoundCardContent(info: info), dark: dark, name: "dock-sound-card")
    }

    @Test(arguments: [true, false])
    func soundCardMuted(dark: Bool) {
        let info = SoundInfo(outputName: "AirPods Pro", volume: 0.4, isMuted: true, inputName: "AirPods Pro")
        assertPanel(DockSoundCardContent(info: info), dark: dark, name: "dock-sound-card-muted")
    }

    @Test(arguments: [true, false])
    func micCameraIdle(dark: Bool) {
        assertPanel(DockMicCameraCardContent(status: CaptureStatus()), dark: dark, name: "dock-mic-card-idle")
    }

    @Test(arguments: [true, false])
    func micCameraInUse(dark: Bool) {
        let status = CaptureStatus(microphones: ["MacBook Pro Microphone"], cameras: ["FaceTime HD Camera"])
        assertPanel(DockMicCameraCardContent(status: status), dark: dark, name: "dock-mic-card-in-use")
    }

    private func makeMonitor(_ reading: SystemMediaReading) -> SystemMonitor {
        SystemMonitor(media: SystemMediaStore(backend: FixedBackend(reading)))
    }

    /// The tile reads only once it has appeared and holds the store, so the store is held here.
    private func tile(_ module: ModuleID, _ reading: SystemMediaReading) -> some View {
        let monitor = makeMonitor(reading)
        monitor.media.retain()
        return WidgetTile(module: module, size: 56, monitor: monitor, click: {}, hold: {}).padding(8)
    }

    @Test(arguments: [true, false])
    func soundTile(dark: Bool) {
        let reading = SystemMediaReading(sound: SoundInfo(outputName: "Speakers", volume: 0.62))
        assertPanel(tile(.sound, reading), width: 72, height: 72, dark: dark, name: "dock-sound-tile")
    }

    @Test(arguments: [true, false])
    func micCameraTileInUse(dark: Bool) {
        let reading = SystemMediaReading(capture: CaptureStatus(cameras: ["FaceTime HD Camera"]))
        assertPanel(tile(.micCamera, reading), width: 72, height: 72, dark: dark, name: "dock-mic-tile-camera")
    }

    @Test(arguments: [true, false])
    func micCameraTileIdle(dark: Bool) {
        assertPanel(
            tile(.micCamera, SystemMediaReading()), width: 72, height: 72, dark: dark, name: "dock-mic-tile-idle"
        )
    }
}

/// A backend with one reading and no listeners, so a tile that appears does not touch the system.
@MainActor
private final class FixedBackend: SystemMediaBackend {
    private let reading: SystemMediaReading

    init(_ reading: SystemMediaReading) {
        self.reading = reading
    }

    func read() -> SystemMediaReading {
        reading
    }

    func startListening(_: @escaping @MainActor () -> Void) {}
    func stopListening() {}
}
