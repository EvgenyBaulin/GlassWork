import AppKit
import CoreAudio
import GlassWorkCore
import WidgetKit

/// Connects the Now Playing store to WidgetKit: writes what widgets show, reloads them within
/// their budget, finds out whether any are on the desktop and takes their button presses.
@MainActor
final class NowPlayingBridge {
    private let store: NowPlayingStore
    private let snapshots = NowPlayingSnapshots()
    private var throttle: ReloadThrottle
    private var pendingReload: Task<Void, Never>?
    private var lastRequest = Date.distantPast
    private(set) var hasSystemWidget = false

    private static let kinds = [WidgetKind.nowPlaying.rawValue, WidgetKind.lyrics.rawValue]

    init(store: NowPlayingStore, refreshSeconds: Int) {
        self.store = store
        throttle = ReloadThrottle(interval: TimeInterval(refreshSeconds))
        store.onChange = { [weak self] in self?.sessionChanged() }
        listenForRequests()
    }

    /// The script that talks to the system, inside the app bundle.
    static func makeStore() -> NowPlayingStore {
        NowPlayingStore(
            makeSource: {
                Bundle.main.url(forResource: "now-playing-adapter", withExtension: "pl").map(NowPlayingAdapter.init)
            },
            appName: { bundleID in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
                    FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
                }
            }
        )
    }

    /// Asks WidgetKit which widgets the user placed. Calls back only when the answer changes.
    func checkSystemWidgets(changed: @escaping @MainActor () -> Void) {
        WidgetCenter.shared.getCurrentConfigurations { [weak self] result in
            let found = (try? result.get())?.contains { Self.kinds.contains($0.kind) } ?? false
            Task { @MainActor in
                guard let self, found != self.hasSystemWidget else { return }
                self.hasSystemWidget = found
                changed()
            }
        }
    }

    /// Widgets must not keep showing a track once nothing can update it.
    func prepareToQuit() {
        try? snapshots.write(nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func sessionChanged() {
        store.outputDevice = store.session == nil ? nil : AudioOutput.currentName()
        try? snapshots.write(store.widgetData)
        reloadWidgets()
    }

    /// Changes that come quickly one after another end in one reload.
    private func reloadWidgets() {
        guard hasSystemWidget, pendingReload == nil else { return }
        let wait = throttle.delay(at: Date())
        guard wait > 0 else {
            Self.reload()
            return
        }
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            pendingReload = nil
            throttle.didReload(at: Date())
            Self.reload()
        }
    }

    private static func reload() {
        kinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
    }

    private func listenForRequests() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let address = UInt(bitPattern: observer)
                Task { @MainActor in
                    let pointer = UnsafeRawPointer(bitPattern: address)
                    guard let pointer else { return }
                    Unmanaged<NowPlayingBridge>.fromOpaque(pointer).takeUnretainedValue().handleRequest()
                }
            },
            NowPlayingRequest.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleRequest() {
        let saved = SnapshotStore().read(NowPlayingRequest.self, for: NowPlayingRequest.key)
        guard let request = saved, request.date != lastRequest, request.isFresh(at: Date()) else { return }
        lastRequest = request.date
        store.perform(request.command)
    }
}

/// The name of the device sound goes to, such as "MacBook Pro Speakers".
enum AudioOutput {
    static func currentName() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr else { return nil }
        address.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}
