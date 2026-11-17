import AudioToolbox
import CoreAudio
import Foundation
import GlassWorkCore

/// What the island needs beyond the monitor's readings: volume and brightness, files being downloaded, and the
/// batteries of headphones the sound just moved to.
///
/// Everything is event-driven. Volume, mute and the default output come from Core Audio listeners. Downloads come
/// from a file-system source on the Downloads folder, which does not report a file growing, so while one is under
/// way the folder is read again every 2 seconds. Brightness has no change notification: one cheap read a second,
/// only while the island is on. Nothing runs while the island is off.
@MainActor
final class IslandFeeds {
    private(set) var levels: SystemLevels?
    private(set) var downloads: [DockFile] = []
    /// Read when the output changes, so the headphones' batteries arrive together with the new output name.
    private(set) var deviceBatteries: [DeviceBattery]?

    private let onChange: () -> Void
    private var isRunning = false

    private var listenedDevice: AudioObjectID?
    private var defaultListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var batteryRead: Task<Void, Never>?
    private var brightnessTimer: Timer?
    /// The previous poll's reading, shown or not: automatic brightness moves it without showing the island.
    private var lastBrightness: Double?

    private var downloadsPath: String?
    private var folderSource: (any DispatchSourceFileSystemObject)?
    private var folderRead: Task<Void, Never>?
    private var following: Task<Void, Never>?

    private static let followInterval = Duration.seconds(2)
    private static let brightnessInterval: TimeInterval = 1

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// - Parameter downloadsPath: The folder to watch: the Dock's Downloads stack, else the user's Downloads
    ///   folder. The first read can raise a macOS access prompt; if access is refused the folder reads as empty.
    ///   nil leaves downloads out.
    func apply(isEnabled: Bool, downloadsPath: String?) {
        guard isEnabled else {
            stop()
            return
        }
        if !isRunning {
            isRunning = true
            levels = SystemLevelsReader.read()
            startAudioListeners()
            startBrightnessTimer()
        }
        watchDownloads(downloadsPath)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopAudioListeners()
        batteryRead?.cancel()
        batteryRead = nil
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        watchDownloads(nil)
        levels = nil
        lastBrightness = nil
        deviceBatteries = nil
    }

    /// For after the island itself sets a level, so its card does not wait for the next poll.
    func refreshLevels() {
        guard isRunning, batteryRead == nil else { return }
        let current = SystemLevelsReader.read()
        guard current != levels else { return }
        levels = current
        onChange()
    }

    // MARK: Volume, mute and the output device

    private static var systemObject: AudioObjectID {
        AudioObjectID(kAudioObjectSystemObject)
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var deviceAddresses: [AudioObjectPropertyAddress] {
        [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute].map {
            AudioObjectPropertyAddress(
                mSelector: $0, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
            )
        }
    }

    private func startAudioListeners() {
        let onDefault: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
        let onDevice: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshLevels() }
        }
        defaultListener = onDefault
        deviceListener = onDevice
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main, onDefault)
        listenDevice(SystemLevelsReader.defaultOutput())
    }

    private func stopAudioListeners() {
        if let defaultListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, .main, defaultListener)
        }
        listenDevice(nil)
        defaultListener = nil
        deviceListener = nil
    }

    /// Moves the volume and mute listeners to another device, or off every device.
    private func listenDevice(_ device: AudioObjectID?) {
        if let listenedDevice, let deviceListener {
            for var address in Self.deviceAddresses {
                AudioObjectRemovePropertyListenerBlock(listenedDevice, &address, .main, deviceListener)
            }
        }
        listenedDevice = device
        guard let device, let deviceListener else { return }
        for var address in Self.deviceAddresses where AudioObjectHasProperty(device, &address) {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, deviceListener)
        }
    }

    /// The batteries are read before the new name is published: the island matches them when the name changes.
    private func outputChanged() {
        guard isRunning else { return }
        listenDevice(SystemLevelsReader.defaultOutput())
        batteryRead?.cancel()
        batteryRead = Task { [weak self] in
            let batteries = await DeviceBatteryReader.read()
            guard let self, !Task.isCancelled, isRunning else { return }
            batteryRead = nil
            deviceBatteries = batteries
            levels = SystemLevelsReader.read()
            onChange()
        }
    }

    // MARK: Brightness

    private func startBrightnessTimer() {
        // Without a readable brightness there is nothing to watch.
        guard SystemLevelsReader.readBrightness() != nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.brightnessInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBrightness() }
        }
        timer.tolerance = Self.brightnessInterval / 2
        brightnessTimer = timer
    }

    private func pollBrightness() {
        guard isRunning, batteryRead == nil, var current = levels else { return }
        let brightness = SystemLevelsReader.readBrightness()
        let previous = lastBrightness ?? current.brightness
        lastBrightness = brightness
        guard IslandFeedRules.brightnessChanged(from: previous, to: brightness) else { return }
        current.brightness = brightness
        levels = current
        onChange()
    }

    // MARK: Downloads

    private func watchDownloads(_ path: String?) {
        guard path != downloadsPath else { return }
        folderSource?.cancel()
        folderSource = nil
        folderRead?.cancel()
        following?.cancel()
        following = nil
        downloadsPath = path
        guard let path else {
            publish([])
            return
        }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readDownloads() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        folderSource = source
        readDownloads()
    }

    private func readDownloads() {
        guard let path = downloadsPath else { return }
        folderRead?.cancel()
        folderRead = Task { [weak self] in
            let found = await Task.detached { DockFolderReader().read(path) }.value
            guard let self, !Task.isCancelled, downloadsPath == path else { return }
            publish(IslandFeedRules.downloads(from: found))
            followDownloads()
        }
    }

    private func publish(_ files: [DockFile]) {
        guard files != downloads else { return }
        downloads = files
        onChange()
    }

    /// A folder reports files coming and going, not growing: while one downloads, look again every 2 seconds.
    private func followDownloads() {
        let isDownloading = downloads.contains(where: \.isDownloading)
        guard isDownloading != (following != nil) else { return }
        following?.cancel()
        following = nil
        guard isDownloading else { return }
        following = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.followInterval)
                guard let self, !Task.isCancelled else { return }
                readDownloads()
            }
        }
    }
}
