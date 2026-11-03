import Foundation
import IOKit

/// Reads properties of IOKit services.
enum IORegistry {
    /// Properties of every service of a class.
    static func properties(ofClass name: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            let status = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
            if status == KERN_SUCCESS, let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] {
                result.append(dictionary)
            }
        }
        return result
    }
}
