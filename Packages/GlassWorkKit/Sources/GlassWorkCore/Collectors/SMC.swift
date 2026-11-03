import Foundation
import IOKit

/// Read-only client of the System Management Controller.
public final class SMCClient: @unchecked Sendable {
    // @unchecked: the connection is an immutable port and calls are serialised by `lock`.
    private let connection: io_connect_t
    private let lock = NSLock()
    private var infoCache: [UInt32: Message.KeyInfo] = [:]

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var handle: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &handle) == KERN_SUCCESS else { return nil }
        connection = handle
    }

    deinit { IOServiceClose(connection) }

    public struct Value: Sendable, Equatable {
        public let type: String
        public let bytes: [UInt8]
    }

    public func read(_ key: String) -> Value? {
        read(FourCC.encode(key))
    }

    public func keyCount() -> Int {
        guard let value = read("#KEY") else { return 0 }
        return Int(value.bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }

    /// Lists keys starting with one of the prefixes.
    public func keys(withPrefixes prefixes: [String]) -> [String] {
        (0 ..< keyCount()).compactMap { index in
            var request = Message()
            request.command = Command.keyAtIndex
            request.index = UInt32(index)
            guard let reply = call(request) else { return nil }
            let key = FourCC.decode(reply.key)
            return prefixes.contains(where: key.hasPrefix) ? key : nil
        }
    }

    private func read(_ key: UInt32) -> Value? {
        guard let info = keyInfo(key) else { return nil }
        var request = Message()
        request.key = key
        request.keyInfo.size = info.size
        request.command = Command.read
        guard let reply = call(request) else { return nil }
        let bytes = withUnsafeBytes(of: reply.bytes) { Array($0.prefix(Int(info.size))) }
        return Value(type: FourCC.decode(info.type), bytes: bytes)
    }

    /// A key's type and size never change, so each is asked for once.
    private func keyInfo(_ key: UInt32) -> Message.KeyInfo? {
        if let cached = lock.withLock({ infoCache[key] }) {
            return cached
        }
        var request = Message()
        request.key = key
        request.command = Command.keyInfo
        guard let info = call(request)?.keyInfo else { return nil }
        lock.withLock { infoCache[key] = info }
        return info
    }

    private func call(_ message: Message) -> Message? {
        lock.lock()
        defer { lock.unlock() }
        var input = message
        var output = Message()
        var size = MemoryLayout<Message>.stride
        let status = IOConnectCallStructMethod(
            connection, Command.selector, &input, MemoryLayout<Message>.stride, &output, &size
        )
        return status == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private enum Command {
        static let selector: UInt32 = 2
        static let read: UInt8 = 5
        static let keyAtIndex: UInt8 = 8
        static let keyInfo: UInt8 = 9
    }

    // swiftlint:disable nesting large_tuple
    /// Mirrors the driver's `SMCKeyData_t`, so field order and sizes must not change.
    private struct Message {
        struct Version {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }

        struct PowerLimit {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpu: UInt32 = 0
            var gpu: UInt32 = 0
            var memory: UInt32 = 0
        }

        struct KeyInfo {
            var size: UInt32 = 0
            var type: UInt32 = 0
            var attributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var version = Version()
        var limit = PowerLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var index: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }
    // swiftlint:enable nesting large_tuple
}

enum FourCC {
    static func encode(_ text: String) -> UInt32 {
        text.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func decode(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(value >> UInt32($0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

public extension SMCClient.Value {
    /// Numeric value for the encodings temperature and fan keys use.
    var number: Double? {
        switch type {
        case "flt " where bytes.count == 4:
            Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "sp78" where bytes.count == 2:
            Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 ", "ui16", "ui32":
            Double(bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        default:
            nil
        }
    }
}
