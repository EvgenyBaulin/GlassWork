import Foundation
import SystemConfiguration

public enum VPNStatus: Sendable, Equatable {
    case disconnected, connecting, connected, disconnecting

    init(_ status: SCNetworkConnectionStatus) {
        switch status {
        case .connected: self = .connected
        case .connecting: self = .connecting
        case .disconnecting: self = .disconnecting
        default: self = .disconnected
        }
    }
}

/// A VPN configured in System Settings.
public struct VPNService: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let status: VPNStatus

    public init(id: String, name: String, kind: String, status: VPNStatus) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
    }
}

/// A tunnel that carries traffic, which may belong to a VPN app System Settings does not know.
public struct TunnelInterface: Sendable, Equatable {
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public struct VPNReading: Sendable, Equatable {
    public let services: [VPNService]
    public let tunnels: [TunnelInterface]

    public init(services: [VPNService], tunnels: [TunnelInterface]) {
        self.services = services
        self.tunnels = tunnels
    }

    public var isConnected: Bool {
        !tunnels.isEmpty || services.contains { $0.status == .connected }
    }

    public var isConnecting: Bool {
        !isConnected && services.contains { $0.status == .connecting }
    }

    public var isConfigured: Bool {
        !services.isEmpty || !tunnels.isEmpty
    }

    public var connectedService: VPNService? {
        services.first { $0.status == .connected }
    }

    public var otherServices: [VPNService] {
        services.filter { $0.id != connectedService?.id }
    }
}

/// One address of a network interface, as `getifaddrs` reports it.
public struct InterfaceAddress: Sendable, Equatable {
    public let interface: String
    public let address: String
    public let isUp: Bool

    public init(interface: String, address: String, isUp: Bool) {
        self.interface = interface
        self.address = address
        self.isUp = isUp
    }
}

public enum TunnelClassifier {
    private static let prefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    /// macOS keeps several `utun` interfaces up for its own services, each with only a link-local
    /// IPv6 address, so an interface counts as a tunnel only once it has a routable address.
    public static func tunnels(_ addresses: [InterfaceAddress]) -> [TunnelInterface] {
        var seen = Set<String>()
        return addresses.compactMap { entry in
            guard entry.isUp,
                  prefixes.contains(where: entry.interface.hasPrefix),
                  isRoutable(entry.address),
                  seen.insert(entry.interface).inserted
            else { return nil }
            return TunnelInterface(name: entry.interface, address: entry.address)
        }
    }

    private static func isRoutable(_ address: String) -> Bool {
        if address.contains(":") {
            // Global unicast is 2000::/3. `fe80::` is link-local and `fd00::/8` stays on the Mac.
            return address.first == "2" || address.first == "3"
        }
        return !address.isEmpty && !address.hasPrefix("169.254.")
    }
}

public enum VPNKind {
    /// The label of a network service, or nil when it is not a VPN.
    public static func name(interfaceType: String, underlyingType: String?) -> String? {
        switch interfaceType {
        case "VPN": "VPN"
        case "IPSec": "IPSec"
        case "PPP" where underlyingType == "L2TP": "L2TP"
        case "PPP" where underlyingType == "PPTP": "PPTP"
        default: nil
        }
    }
}

public enum VPNReader {
    public static func read() -> VPNReading {
        VPNReading(services: services(), tunnels: TunnelClassifier.tunnels(addresses()))
    }

    private static func services() -> [VPNService] {
        guard let preferences = SCPreferencesCreate(nil, "GlassWork" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(preferences),
              let all = SCNetworkSetCopyServices(set) as? [SCNetworkService]
        else { return [] }
        return all.compactMap(service)
    }

    private static func service(_ service: SCNetworkService) -> VPNService? {
        guard SCNetworkServiceGetEnabled(service),
              let interface = SCNetworkServiceGetInterface(service),
              let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
              let id = SCNetworkServiceGetServiceID(service) as String?
        else { return nil }
        let underlying = SCNetworkInterfaceGetInterface(interface).flatMap {
            SCNetworkInterfaceGetInterfaceType($0) as String?
        }
        guard let kind = VPNKind.name(interfaceType: type, underlyingType: underlying) else { return nil }
        let connection = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, nil, nil)
        return VPNService(
            id: id,
            name: SCNetworkServiceGetName(service) as String? ?? kind,
            kind: kind,
            status: connection.map { VPNStatus(SCNetworkConnectionGetStatus($0)) } ?? .disconnected
        )
    }

    private static func addresses() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var result: [InterfaceAddress] = []
        var cursor = head
        while let entry = cursor?.pointee {
            cursor = entry.ifa_next
            guard let socket = entry.ifa_addr,
                  [AF_INET, AF_INET6].contains(Int32(socket.pointee.sa_family))
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(socket.pointee.sa_len)
            guard getnameinfo(socket, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            result.append(InterfaceAddress(
                interface: String(cString: entry.ifa_name),
                address: String(cString: host),
                isUp: entry.ifa_flags & UInt32(IFF_UP) != 0
            ))
        }
        return result
    }
}
