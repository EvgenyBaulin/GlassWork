import Darwin
import Foundation

/// Cumulative byte counters of one interface.
public struct InterfaceCounters: Sendable, Equatable {
    public var name: String
    public var received: UInt64
    public var sent: UInt64

    public init(name: String, received: UInt64, sent: UInt64) {
        self.name = name
        self.received = received
        self.sent = sent
    }
}

public struct NetworkSample: Codable, Sendable, Equatable {
    public struct Interface: Codable, Sendable, Equatable {
        public var name: String
        public var download: Double
        public var upload: Double
    }

    /// Bytes per second.
    public var download: Double
    public var upload: Double
    public var interfaces: [Interface]
    public var sessionReceived: UInt64
    public var sessionSent: UInt64

    /// Physical interfaces only: tunnels and virtual links would count the same traffic twice.
    public static func isPhysical(_ name: String) -> Bool {
        name.hasPrefix("en")
    }

    public static func between(
        _ previous: [InterfaceCounters],
        _ current: [InterfaceCounters],
        seconds: TimeInterval,
        sessionReceived: UInt64 = 0,
        sessionSent: UInt64 = 0
    ) -> NetworkSample {
        let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0) })
        var interfaces: [Interface] = []
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for counters in current where isPhysical(counters.name) {
            guard let before = old[counters.name] else { continue }
            // Counters restart when an interface comes back up; that interval reads as zero.
            let inBytes = counters.received >= before.received ? counters.received - before.received : 0
            let outBytes = counters.sent >= before.sent ? counters.sent - before.sent : 0
            received += inBytes
            sent += outBytes
            if inBytes > 0 || outBytes > 0 {
                interfaces.append(Interface(
                    name: counters.name,
                    download: Double(inBytes) / max(seconds, 0.001),
                    upload: Double(outBytes) / max(seconds, 0.001)
                ))
            }
        }
        return NetworkSample(
            download: Double(received) / max(seconds, 0.001),
            upload: Double(sent) / max(seconds, 0.001),
            interfaces: interfaces,
            sessionReceived: sessionReceived + received,
            sessionSent: sessionSent + sent
        )
    }
}

public enum NetworkReader {
    /// IPv4 address of the first active physical interface.
    public static func localAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  NetworkSample.isPhysical(String(cString: interface.ifa_name)),
                  interface.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            )
            if status == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    /// Asks an echo service for the public address. Only runs after the user turns it on.
    public static func publicAddress() async -> String? {
        guard let url = URL(string: "https://api.ipify.org"),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 64-bit counters from the routing table: `getifaddrs` wraps at 4 GB.
    public static func counters() -> [InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [] }

        var result: [InterfaceCounters] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                defer { offset += Int(header.ifm_msglen) }
                guard header.ifm_msglen > 0, Int32(header.ifm_type) == RTM_IFINFO2 else { continue }
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                guard if_indextoname(UInt32(message.ifm_index), &name) != nil else { continue }
                result.append(InterfaceCounters(
                    name: String(cString: name),
                    received: message.ifm_data.ifi_ibytes,
                    sent: message.ifm_data.ifi_obytes
                ))
            }
        }
        return result
    }
}
