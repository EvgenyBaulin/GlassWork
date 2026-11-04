import CoreWLAN
import Foundation

public enum WiFiBand: Int, Codable, Sendable, Equatable {
    case unknown, ghz2, ghz5, ghz6

    public var title: String {
        switch self {
        case .unknown: "—"
        case .ghz2: "2.4 GHz"
        case .ghz5: "5 GHz"
        case .ghz6: "6 GHz"
        }
    }
}

public enum WiFiQuality: Sendable, Equatable {
    case excellent, good, fair, weak
}

/// Everything shown about the current link. The network's name is deliberately not here.
public struct WiFiLink: Codable, Sendable, Equatable {
    public let rssi: Int
    public let noise: Int
    public let transmitRate: Double
    public let channel: Int
    public let band: WiFiBand
    /// Channel width in MHz, nil when unknown.
    public let width: Int?
    /// Standard such as `802.11ax (Wi-Fi 6)`, nil when unknown.
    public let standard: String?

    public init(
        rssi: Int,
        noise: Int,
        transmitRate: Double,
        channel: Int,
        bandCode: Int,
        widthCode: Int,
        phyCode: Int
    ) {
        self.rssi = rssi
        self.noise = noise
        self.transmitRate = transmitRate
        self.channel = channel
        band = WiFiBand(rawValue: bandCode) ?? .unknown
        width = [1: 20, 2: 40, 3: 80, 4: 160][widthCode]
        standard = Self.standards[phyCode]
    }

    private static let standards = [
        1: "802.11a",
        2: "802.11b",
        3: "802.11g",
        4: "802.11n (Wi-Fi 4)",
        5: "802.11ac (Wi-Fi 5)",
        6: "802.11ax (Wi-Fi 6)",
        7: "802.11be (Wi-Fi 7)",
    ]

    public var signalToNoise: Int {
        rssi - noise
    }

    /// Arcs of the menu bar symbol, out of three.
    public var bars: Int {
        if rssi >= -60 {
            return 3
        }
        return rssi >= -70 ? 2 : 1
    }

    public var quality: WiFiQuality {
        if rssi >= -50 {
            return .excellent
        }
        if rssi >= -60 {
            return .good
        }
        return rssi >= -70 ? .fair : .weak
    }
}

public enum WiFiReading: Codable, Sendable, Equatable {
    case noHardware, off, notConnected
    case connected(WiFiLink)

    public var link: WiFiLink? {
        if case let .connected(link) = self {
            return link
        }
        return nil
    }
}

/// Charts plot this above zero, because dBm values are negative.
public enum WiFiSignal {
    public static let floor = -100.0
    public static let domain = 0.0 ... 70.0

    public static func plotted(_ rssi: Int) -> Double {
        Double(rssi) - floor
    }

    public static func rssi(plotted value: Double) -> Int {
        Int((value + floor).rounded())
    }
}

public enum WiFiReader {
    /// Reads link quality only. Never call `ssid`, `ssidData`, `bssid`, scans, `cachedScanResults`
    /// or `configuration`: the network's name is off limits and would need Location permission.
    public static func read() -> WiFiReading {
        guard let interface = CWWiFiClient.shared().interface() else { return .noHardware }
        guard interface.powerOn() else { return .off }
        let rssi = interface.rssiValue()
        guard rssi != 0, let channel = interface.wlanChannel() else { return .notConnected }
        return .connected(WiFiLink(
            rssi: rssi,
            noise: interface.noiseMeasurement(),
            transmitRate: interface.transmitRate(),
            channel: channel.channelNumber,
            bandCode: channel.channelBand.rawValue,
            widthCode: channel.channelWidth.rawValue,
            phyCode: interface.activePHYMode().rawValue
        ))
    }
}
