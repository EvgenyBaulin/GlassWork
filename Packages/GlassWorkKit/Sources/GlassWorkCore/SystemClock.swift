import Darwin
import Foundation

/// System boot time and uptime.
public enum SystemClock {
    /// The moment the Mac started, read from `kern.boottime`.
    public static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else { return nil }
        let seconds = Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
        return Date(timeIntervalSince1970: seconds)
    }
}
