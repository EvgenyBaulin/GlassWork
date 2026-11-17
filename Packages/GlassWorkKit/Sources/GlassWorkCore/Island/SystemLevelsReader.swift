import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation

/// Reads and sets the output volume (Core Audio) and the built-in display's brightness.
///
/// Brightness has no public API: it goes through DisplayServices, loaded at run time. When the framework or its
/// functions are missing, brightness reads nil and cannot be set, and nothing else is affected.
public enum SystemLevelsReader {
    public static func read() -> SystemLevels {
        let device = defaultOutput()
        return SystemLevels(
            volume: device.flatMap(volume(of:)),
            isMuted: device.flatMap(isMuted(_:)) ?? false,
            outputName: device.flatMap(name(of:)),
            brightness: Brightness.get()
        )
    }

    public static func setVolume(_ value: Double) {
        guard let device = defaultOutput() else { return }
        var level = Float32(min(max(value, 0), 1))
        var address = property(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
        if level > 0, isMuted(device) == true {
            var off: UInt32 = 0
            var mute = property(kAudioDevicePropertyMute)
            AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
        }
    }

    /// Brightness alone, for a cheap check.
    public static func readBrightness() -> Double? {
        Brightness.get()
    }

    public static var canSetBrightness: Bool {
        Brightness.set != nil && Brightness.get() != nil
    }

    public static func setBrightness(_ value: Double) {
        Brightness.setLevel(min(max(value, 0), 1))
    }

    static func property(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    public static func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = property(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func volume(of device: AudioObjectID) -> Double? {
        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = property(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr
        else { return nil }
        return Double(level)
    }

    static func isMuted(_ device: AudioObjectID) -> Bool? {
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = property(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else { return nil }
        return muted != 0
    }

    static func name(of device: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = property(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else {
            return nil
        }
        return name.takeRetainedValue() as String
    }
}

/// DisplayServices, looked up once.
private enum Brightness {
    typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Setter = @convention(c) (UInt32, Float) -> Int32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        return dlsym(handle, name)
    }

    private static let getter: Getter? = symbol("DisplayServicesGetBrightness").map {
        unsafeBitCast($0, to: Getter.self)
    }

    static let set: Setter? = symbol("DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Setter.self) }

    static func get() -> Double? {
        guard let getter else { return nil }
        var level = Float(0)
        return getter(CGMainDisplayID(), &level) == 0 ? Double(level) : nil
    }

    static func setLevel(_ value: Double) {
        _ = set?(CGMainDisplayID(), Float(value))
    }
}
