import AudioToolbox
import CoreAudio
import CoreMediaIO
import Foundation

/// Reads sound and capture state from Core Audio and CoreMediaIO, and listens for changes to it.
///
/// Whether a device is running comes from `kAudioDevicePropertyDeviceIsRunningSomewhere` (microphones) and
/// `kCMIODevicePropertyDeviceIsRunningSomewhere` (cameras). Both are public and need no permission, and neither
/// says which app uses the device. Everything is event-driven: listeners sit on the default devices, the device
/// lists (so a plugged-in camera is noticed) and each device that matters, and are moved when the set changes.
@MainActor
public final class CoreMediaBackend: SystemMediaBackend {
    /// The objects that carry listeners now. Compared after every event, so listeners move with the devices.
    private struct Targets: Equatable {
        var output: AudioObjectID?
        var microphones: [AudioObjectID] = []
        var cameras: [CMIOObjectID] = []
    }

    private var onChange: (@MainActor () -> Void)?
    private var audioBlock: AudioObjectPropertyListenerBlock?
    private var cameraBlock: CMIOObjectPropertyListenerBlock?
    private var wired: Targets?
    private var audioRegistrations: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private var cameraRegistrations: [(CMIOObjectID, CMIOObjectPropertyAddress)] = []

    public init() {}

    // MARK: Reading

    public func read() -> SystemMediaReading {
        let output = SystemLevelsReader.defaultOutput()
        let input = Self.defaultInput()
        let sound = SoundInfo(
            outputName: output.flatMap(SystemLevelsReader.name(of:)),
            volume: output.flatMap(SystemLevelsReader.volume(of:)),
            isMuted: output.flatMap(SystemLevelsReader.isMuted(_:)) ?? false,
            inputName: input.flatMap(SystemLevelsReader.name(of:))
        )
        let microphones = Self.microphones().filter(Self.isRunning(audio:)).compactMap(SystemLevelsReader.name(of:))
        let cameras = Self.cameras().filter(Self.isRunning(camera:)).map { Self.name(ofCamera: $0) ?? "" }
        return SystemMediaReading(sound: sound, capture: CaptureStatus(microphones: microphones, cameras: cameras))
    }

    // MARK: Listening

    public func startListening(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        audioBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        cameraBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        wire()
    }

    public func stopListening() {
        unwire()
        onChange = nil
        audioBlock = nil
        cameraBlock = nil
    }

    private func changed() {
        guard onChange != nil else { return }
        wire()
        onChange?()
    }

    private func wire() {
        let targets = Targets(
            output: SystemLevelsReader.defaultOutput(),
            microphones: Self.microphones(),
            cameras: Self.cameras()
        )
        guard targets != wired else { return }
        unwire()
        wired = targets
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDevices,
        ] {
            add(system, Self.address(selector, scope: kAudioObjectPropertyScopeGlobal))
        }
        if let output = targets.output {
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                add(output, Self.address(selector, scope: kAudioDevicePropertyScopeOutput))
            }
        }
        for microphone in targets.microphones {
            add(microphone, Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere))
        }
        let cameraSystem = CMIOObjectID(kCMIOObjectSystemObject)
        add(cameraSystem, Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)))
        for camera in targets.cameras {
            add(camera, Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)))
        }
    }

    private func unwire() {
        if let audioBlock {
            for (object, address) in audioRegistrations {
                var address = address
                AudioObjectRemovePropertyListenerBlock(object, &address, .main, audioBlock)
            }
        }
        if let cameraBlock {
            for (object, address) in cameraRegistrations {
                var address = address
                CMIOObjectRemovePropertyListenerBlock(object, &address, .main, cameraBlock)
            }
        }
        audioRegistrations = []
        cameraRegistrations = []
        wired = nil
    }

    private func add(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        guard let audioBlock, AudioObjectHasProperty(object, &address),
              AudioObjectAddPropertyListenerBlock(object, &address, .main, audioBlock) == noErr
        else { return }
        audioRegistrations.append((object, address))
    }

    private func add(_ object: CMIOObjectID, _ address: CMIOObjectPropertyAddress) {
        var address = address
        guard let cameraBlock, CMIOObjectHasProperty(object, &address),
              CMIOObjectAddPropertyListenerBlock(object, &address, .main, cameraBlock) == noErr
        else { return }
        cameraRegistrations.append((object, address))
    }

    // MARK: Core Audio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultInput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Every audio device that has an input.
    static func microphones() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter(hasInput(_:))
    }

    private static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isRunning(audio device: AudioObjectID) -> Bool {
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    // MARK: CoreMediaIO

    private static func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func cameras() -> [CMIOObjectID] {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size = UInt32(0)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used = UInt32(0)
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return [] }
        return devices
    }

    private static func isRunning(camera device: CMIOObjectID) -> Bool {
        var running = UInt32(0)
        var used = UInt32(0)
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        let size = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == noErr && running != 0
    }

    private static func name(ofCamera device: CMIOObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var used = UInt32(0)
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOObjectPropertyName))
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &name) == noErr, let name else {
            return nil
        }
        return name.takeRetainedValue() as String
    }
}
