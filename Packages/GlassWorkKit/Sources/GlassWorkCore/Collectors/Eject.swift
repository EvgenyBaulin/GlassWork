import Foundation

/// Which volumes the Eject module offers, in its panel and on widgets.
public struct EjectOptions: Sendable, Equatable {
    public var asksFirst = true
    public var includesImages = true
    public var includesNetwork = false
    /// Volume names. A drive that always stays plugged in, such as a backup disk, should not go with Eject All.
    public var neverEject: Set<String> = []

    public init() {}

    public init(options: [String: String]) {
        asksFirst = options.flag(ItemOption.ejectAsksFirst, default: true)
        includesImages = options.flag(ItemOption.ejectIncludesImages, default: true)
        includesNetwork = options.flag(ItemOption.ejectIncludesNetwork, default: false)
        neverEject = Self.names(options[ItemOption.ejectNever])
    }

    /// Names as typed in Settings, separated by commas. Case does not matter.
    static func names(_ text: String?) -> Set<String> {
        Set((text ?? "").split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty })
    }

    public func allows(_ volume: DiskVolume) -> Bool {
        guard !neverEject.contains(volume.name.lowercased()) else { return false }
        if volume.isNetwork == true {
            return includesNetwork
        }
        if volume.isDiskImage == true {
            return includesImages
        }
        return volume.isEjectable
    }
}
