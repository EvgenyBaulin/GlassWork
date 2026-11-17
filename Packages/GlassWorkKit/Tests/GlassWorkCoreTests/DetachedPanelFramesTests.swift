import CoreGraphics
import Foundation
@testable import GlassWorkCore
import Testing

struct DetachedPanelFramesTests {
    private let main = DisplayInfo(id: 1, name: "Built-in", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 860))
    private let side = DisplayInfo(
        id: 2,
        name: "Studio",
        visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1380)
    )
    private let now = Date(timeIntervalSince1970: 1_793_750_000)

    @Test func aFrameInsideTheScreenIsKept() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 500)
        #expect(DetachedPanelMemory.clamp(frame, to: main.visibleFrame) == frame)
    }

    @Test func aFrameHangingOffTheScreenIsPulledBack() {
        let frame = CGRect(x: 1300, y: -50, width: 400, height: 500)
        let clamped = DetachedPanelMemory.clamp(frame, to: main.visibleFrame)
        #expect(clamped == CGRect(x: 1040, y: 0, width: 400, height: 500))
    }

    @Test func sizesStayBetweenTheLimits() {
        let small = DetachedPanelMemory.clamp(CGRect(x: 0, y: 0, width: 50, height: 50), to: main.visibleFrame)
        #expect(small.size == DetachedPanelMemory.minimumSize)
        let large = DetachedPanelMemory.clamp(CGRect(x: 0, y: 0, width: 5000, height: 5000), to: side.visibleFrame)
        #expect(large.size == DetachedPanelMemory.maximumSize)
    }

    @Test func aWindowNeverGetsBiggerThanTheScreen() {
        let tiny = DisplayInfo(id: 3, name: "Tiny", visibleFrame: CGRect(x: 0, y: 0, width: 280, height: 200))
        let clamped = DetachedPanelMemory.clamp(CGRect(x: 0, y: 0, width: 400, height: 400), to: tiny.visibleFrame)
        #expect(clamped.size == CGSize(width: 280, height: 200))
    }

    @Test func nothingSavedMeansNothingToRestore() {
        let memory = DetachedPanelMemory()
        #expect(memory.frame(for: .cpu, preferred: main, displays: [main, side]) == nil)
    }

    @Test func eachModuleAndDisplayKeepsItsOwnFrame() {
        var memory = DetachedPanelMemory()
        memory.remember(.cpu, frame: CGRect(x: 10, y: 10, width: 320, height: 400), on: main, at: now)
        memory.remember(
            .cpu,
            frame: CGRect(x: 1500, y: 20, width: 500, height: 600),
            on: side,
            at: now.addingTimeInterval(1)
        )
        memory.remember(.memory, frame: CGRect(x: 50, y: 50, width: 340, height: 300), on: main, at: now)
        #expect(memory.records.count == 3)
        #expect(memory.frame(for: .cpu, preferred: main, displays: [main, side]) == CGRect(
            x: 10,
            y: 10,
            width: 320,
            height: 400
        ))
        #expect(memory.frame(for: .cpu, preferred: side, displays: [main, side]) == CGRect(
            x: 1500,
            y: 20,
            width: 500,
            height: 600
        ))
        #expect(memory.frame(for: .memory, preferred: main, displays: [main, side]) == CGRect(
            x: 50,
            y: 50,
            width: 340,
            height: 300
        ))
    }

    @Test func theKeyNamesTheModuleAndTheDisplay() {
        #expect(DetachedPanelMemory.key(.cpu, display: side) == "cpu@2")
    }

    @Test func aDisplayWithoutARecordFallsBackToTheNewestConnectedOne() {
        var memory = DetachedPanelMemory()
        memory.remember(.cpu, frame: CGRect(x: 1500, y: 20, width: 500, height: 600), on: side, at: now)
        #expect(memory.frame(for: .cpu, preferred: main, displays: [main, side]) == CGRect(
            x: 1500,
            y: 20,
            width: 500,
            height: 600
        ))
    }

    @Test func aMissingDisplayBringsTheFrameOntoThePreferredOne() {
        var memory = DetachedPanelMemory()
        memory.remember(.cpu, frame: CGRect(x: 3000, y: 900, width: 500, height: 600), on: side, at: now)
        let frame = memory.frame(for: .cpu, preferred: main, displays: [main])
        #expect(frame == CGRect(x: 940, y: 260, width: 500, height: 600))
        #expect(main.visibleFrame.contains(frame ?? .zero))
    }

    @Test func aReconnectedDisplayIsRecognizedByName() {
        var memory = DetachedPanelMemory()
        memory.remember(.cpu, frame: CGRect(x: 1500, y: 20, width: 500, height: 600), on: side, at: now)
        let renumbered = DisplayInfo(id: 9, name: "Studio", visibleFrame: side.visibleFrame)
        #expect(memory.frame(for: .cpu, preferred: renumbered, displays: [main, renumbered])
            == CGRect(x: 1500, y: 20, width: 500, height: 600))
    }

    @Test func anExactIdMatchBeatsANameMatch() {
        var memory = DetachedPanelMemory()
        let twinA = DisplayInfo(id: 5, name: "Dell", visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000))
        let twinB = DisplayInfo(id: 6, name: "Dell", visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1000))
        memory.remember(.cpu, frame: CGRect(x: 100, y: 100, width: 400, height: 400), on: twinA, at: now)
        memory.remember(
            .cpu,
            frame: CGRect(x: 2000, y: 100, width: 500, height: 500),
            on: twinB,
            at: now.addingTimeInterval(-5)
        )
        let frame = memory.frame(for: .cpu, preferred: twinB, displays: [twinA, twinB])
        #expect(frame == CGRect(x: 2000, y: 100, width: 500, height: 500))
    }

    @Test func aNameSharedByTwoDisplaysIsNotAMatch() {
        var memory = DetachedPanelMemory()
        let old = DisplayInfo(id: 5, name: "Dell", visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000))
        memory.remember(.cpu, frame: CGRect(x: 100, y: 100, width: 400, height: 400), on: old, at: now)
        let twinA = DisplayInfo(id: 7, name: "Dell", visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000))
        let twinB = DisplayInfo(id: 8, name: "Dell", visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1000))
        // Neither display can be told apart, so the frame is brought onto the preferred one, not matched by name.
        let frame = memory.frame(for: .cpu, preferred: twinB, displays: [twinA, twinB])
        #expect(frame == CGRect(x: 1920, y: 100, width: 400, height: 400))
    }

    @Test func anUnchangedFrameIsRecognized() {
        var memory = DetachedPanelMemory()
        let frame = CGRect(x: 10, y: 10, width: 320, height: 400)
        #expect(!memory.isCurrent(.cpu, frame: frame, on: main))
        memory.remember(.cpu, frame: frame, on: main, at: now)
        #expect(memory.isCurrent(.cpu, frame: frame, on: main))
        #expect(!memory.isCurrent(.cpu, frame: frame.offsetBy(dx: 1, dy: 0), on: main))
        #expect(!memory.isCurrent(.memory, frame: frame, on: main))
    }

    @Test func aSmallerScreenShrinksAndMovesTheSavedFrame() {
        var memory = DetachedPanelMemory()
        memory.remember(.cpu, frame: CGRect(x: 2000, y: 100, width: 600, height: 1200), on: main, at: now)
        let frame = memory.frame(for: .cpu, preferred: main, displays: [main])
        #expect(frame == CGRect(x: 840, y: 0, width: 600, height: 860))
    }

    @Test func theMemorySurvivesTheSettingsFile() throws {
        var settings = AppSettings()
        settings.detachedPanels.remember(.cpu, frame: CGRect(x: 10, y: 20, width: 320, height: 400), on: main, at: now)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.detachedPanels == settings.detachedPanels)
    }

    @Test func aFileWithoutTheKeyStillLoads() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.detachedPanels.records.isEmpty)
    }
}
