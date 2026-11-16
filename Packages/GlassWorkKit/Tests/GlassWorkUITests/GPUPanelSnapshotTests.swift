import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

/// The GPU panel with one GPU, with two, and with a driver that reports no utilization.
@MainActor
struct GPUPanelSnapshotTests {
    private static let gib: UInt64 = 1 << 30

    private static let integrated = GPUSample(
        name: "Intel UHD Graphics 630",
        device: 0.12,
        renderer: 0.1,
        tiler: 0.08,
        memoryInUse: 3 * gib / 2
    )
    private static let discrete = GPUSample(
        name: "AMD Radeon Pro 5500M",
        device: 0.64,
        renderer: 0.6,
        tiler: 0.31,
        memoryInUse: 3 * gib
    )

    private func points(_: TieredHistory.Range) -> [History<Double>.Point] {
        (0 ..< 30).map { index in
            .init(date: sampleNow.addingTimeInterval(Double(index - 30) * 2), value: 0.2 + 0.015 * Double(index))
        }
    }

    @Test(arguments: [false, true])
    func oneGPU(dark: Bool) {
        let view = GPUPanelContent(gpus: [Self.discrete], points: points)
        assertPanel(view, dark: dark, name: "gpu")
    }

    @Test(arguments: [false, true])
    func twoGPUsGetABlockEach(dark: Bool) {
        let view = GPUPanelContent(gpus: [Self.discrete, Self.integrated], points: points)
        assertPanel(view, dark: dark, name: "gpu-two")
    }

    @Test(arguments: [false, true])
    func unreportedUtilizationIsNotZero(dark: Bool) {
        let silent = GPUSample(name: "Virtual GPU", device: 0, isReported: false, memoryInUse: 0)
        assertPanel(GPUPanelContent(gpus: [silent], points: points), dark: dark, name: "gpu-not-reported")
    }
}
