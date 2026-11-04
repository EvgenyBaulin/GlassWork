import Foundation
import GlassWorkCore
import IOKit

/// The only code in the project that can write to the SMC. It needs root, and lives in this target
/// so that the app and the tests cannot reach it. Everything else goes through `FanSMCAccess`.
final class SMCWriter: FanSMCAccess {
    private static let selector: UInt32 = 2
    private static let writeCommand: UInt8 = 6

    private let reader: SMCClient
    private let connection: io_connect_t

    init?() {
        guard let reader = SMCClient() else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var handle: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &handle) == KERN_SUCCESS else { return nil }
        self.reader = reader
        connection = handle
    }

    deinit { IOServiceClose(connection) }

    func read(_ key: String) -> SMCClient.Value? {
        reader.read(key)
    }

    func write(_ key: String, bytes: [UInt8]) -> Bool {
        guard FanHelperService.isWritable(key),
              let current = reader.read(key),
              current.bytes.count == bytes.count,
              bytes.count <= MemoryLayout<SMCMessage>.size
        else { return false }
        var input = SMCMessage()
        input.key = FourCC.encode(key)
        input.keyInfo.size = UInt32(bytes.count)
        input.keyInfo.type = FourCC.encode(current.type)
        input.command = Self.writeCommand
        withUnsafeMutableBytes(of: &input.bytes) { $0.copyBytes(from: bytes) }
        var output = SMCMessage()
        var size = MemoryLayout<SMCMessage>.stride
        let status = IOConnectCallStructMethod(
            connection, Self.selector, &input, MemoryLayout<SMCMessage>.stride, &output, &size
        )
        return status == KERN_SUCCESS && output.result == 0
    }
}
