@testable import GlassWorkCore
import Testing

struct CompactDurationTests {
    @Test(arguments: [
        (0.0, "0s"),
        (45.9, "45s"),
        (60, "1m"),
        (7740, "2h 9m"),
        (273_600, "3d 4h"),
        (-5, "0s"),
    ])
    func formats(interval: Double, expected: String) {
        #expect(CompactDuration.format(interval) == expected)
    }
}
