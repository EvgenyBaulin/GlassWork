import CoreGraphics
import Foundation
@testable import GlassWorkCore
import Testing

/// A 1512×982 laptop: 37-point menu bar, 70-point Dock at the bottom.
private let laptop = TileDisplay(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 875)
)
/// To the right of the laptop and hanging 300 points below it, with a menu bar of its own.
private let rightMonitor = TileDisplay(
    frame: CGRect(x: 1512, y: -300, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1512, y: -300, width: 2560, height: 1415)
)
/// To the left of the laptop, so all of its x values are negative.
private let leftMonitor = TileDisplay(
    frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)
)
/// Above the laptop, so Accessibility gives it negative y values.
private let topMonitor = TileDisplay(
    frame: CGRect(x: 0, y: 982, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 982, width: 1920, height: 1055)
)

private let app: Int32 = 42
private let freeWindow = CGRect(x: 300, y: 300, width: 700, height: 400)

private func expectExactCover(_ frames: [CGRect], of visible: CGRect) {
    let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
    #expect(union == visible)
    #expect(frames.map { $0.width * $0.height }.reduce(0, +) == visible.width * visible.height)
}

struct TileLayoutTests {
    private let visible = CGRect(x: 0, y: 70, width: 1512, height: 875)

    @Test func thereAreTwelveLayouts() {
        #expect(TileLayout.allCases.count == 12)
    }

    @Test func halvesFillTheirSideOfTheVisibleFrame() {
        #expect(TileTarget(.leftHalf).frame(in: visible) == CGRect(x: 0, y: 70, width: 756, height: 875))
        #expect(TileTarget(.rightHalf).frame(in: visible) == CGRect(x: 756, y: 70, width: 756, height: 875))
    }

    /// The system's y grows upward, so the top of the screen is the largest y.
    @Test func topMeansTheHighestYValues() {
        let top = TileTarget(.topHalf).frame(in: visible)
        let bottom = TileTarget(.bottomHalf).frame(in: visible)
        #expect(top.maxY == visible.maxY)
        #expect(top.minX == visible.minX && top.width == visible.width)
        #expect(bottom.minY == visible.minY)
        #expect(top.minY == bottom.maxY)
        #expect(TileTarget(.topLeft).frame(in: visible).maxY == visible.maxY)
        #expect(TileTarget(.topRight).frame(in: visible).maxY == visible.maxY)
        #expect(TileTarget(.bottomLeft).frame(in: visible).minY == visible.minY)
        #expect(TileTarget(.bottomRight).frame(in: visible).minY == visible.minY)
    }

    @Test func fullScreenIsTheVisibleFrameAndNotTheDisplay() {
        #expect(TileTarget(.fullScreen).frame(in: visible) == visible)
    }

    @Test func centerTakesTheShareDrawnInTheDesign() {
        let frame = TileTarget(.center).frame(in: CGRect(x: 0, y: 0, width: 1300, height: 700))
        #expect(frame == CGRect(x: 260, y: 105, width: 780, height: 490))
    }

    @Test func thirdsSitAtTheOuterEdges() {
        #expect(TileTarget(.firstThird).frame(in: visible) == CGRect(x: 0, y: 70, width: 504, height: 875))
        #expect(TileTarget(.lastThird).frame(in: visible) == CGRect(x: 1008, y: 70, width: 504, height: 875))
    }

    /// 1513 and 877 do not divide evenly: a one-point seam would show the desktop through.
    @Test(arguments: [
        CGSize(width: 1513, height: 877),
        CGSize(width: 1000, height: 701),
        CGSize(width: 1367, height: 767)
    ])
    func oddSizesLeaveNoGapAndNoOverlap(size: CGSize) {
        let odd = CGRect(origin: CGPoint(x: -311, y: 45), size: size)
        let halves: [TileLayout] = [.leftHalf, .rightHalf]
        expectExactCover(halves.map { TileTarget($0).frame(in: odd) }, of: odd)
        let rows: [TileLayout] = [.topHalf, .bottomHalf]
        expectExactCover(rows.map { TileTarget($0).frame(in: odd) }, of: odd)
        let quarters: [TileLayout] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        expectExactCover(quarters.map { TileTarget($0).frame(in: odd) }, of: odd)
        // Two thirds on one side and one third on the other.
        expectExactCover([TileTarget(.leftHalf, step: 1), TileTarget(.lastThird)].map { $0.frame(in: odd) }, of: odd)
        expectExactCover([TileTarget(.firstThird), TileTarget(.rightHalf, step: 1)].map { $0.frame(in: odd) }, of: odd)
        expectExactCover(
            [TileTarget(.topHalf, step: 1), TileTarget(.bottomHalf, step: 2)].map { $0.frame(in: odd) },
            of: odd
        )
    }

    @Test func innerEdgesLandOnWholePoints() {
        let odd = CGRect(x: 0, y: 25, width: 1513, height: 877)
        for target in TileTarget.all {
            let frame = target.frame(in: odd)
            #expect(frame.minX == frame.minX.rounded())
            #expect(frame.maxX == frame.maxX.rounded())
            #expect(frame.minY == frame.minY.rounded())
            #expect(frame.maxY == frame.maxY.rounded())
        }
    }

    /// A menu bar height with a fraction must not push a window under the menu bar by rounding the outer edge.
    @Test func outerEdgesStayOnAFractionalVisibleFrame() {
        let fractional = CGRect(x: 0, y: 0.5, width: 1000, height: 800.25)
        let frame = TileTarget(.fullScreen).frame(in: fractional)
        #expect(frame == fractional)
    }

    @Test func everyTargetStaysInsideTheVisibleFrame() {
        for target in TileTarget.all {
            #expect(visible.contains(target.frame(in: visible)))
        }
    }

    @Test func onlyHalvesHaveMoreThanOneStep() {
        let halves: Set<TileLayout> = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
        for layout in TileLayout.allCases {
            #expect(layout.stepCount == (halves.contains(layout) ? 3 : 1))
        }
        #expect(TileTarget.all.count == 20)
    }
}

struct ScreenSpaceTests {
    private let primaryHeight = 982.0

    @Test func flippingTwiceGivesTheSameRectangle() {
        for rect in [freeWindow, rightMonitor.frame, leftMonitor.frame, topMonitor.frame] {
            let there = ScreenSpace.flipped(rect, primaryHeight: primaryHeight)
            #expect(ScreenSpace.flipped(there, primaryHeight: primaryHeight) == rect)
        }
    }

    @Test func topOfThePrimaryDisplayIsZero() {
        #expect(ScreenSpace.flipped(laptop.frame, primaryHeight: primaryHeight).minY == 0)
    }

    @Test func theVisibleFrameStartsBelowTheMenuBar() {
        #expect(ScreenSpace.flipped(laptop.visibleFrame, primaryHeight: primaryHeight).minY == 37)
    }

    @Test func aDisplayAboveThePrimaryHasNegativeY() {
        let flipped = ScreenSpace.flipped(topMonitor.frame, primaryHeight: primaryHeight)
        #expect(flipped == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    @Test func aDisplayHangingBelowThePrimaryKeepsItsOffset() {
        let flipped = ScreenSpace.flipped(rightMonitor.frame, primaryHeight: primaryHeight)
        #expect(flipped == CGRect(x: 1512, y: -158, width: 2560, height: 1440))
    }

    @Test func aDisplayOnTheLeftKeepsNegativeX() {
        let flipped = ScreenSpace.flipped(leftMonitor.frame, primaryHeight: primaryHeight)
        #expect(flipped == CGRect(x: -1920, y: -98, width: 1920, height: 1080))
    }

    /// Other displays must be measured against the primary's height and not against their own.
    @Test func aTileOnASecondDisplayUsesThePrimaryHeight() {
        let top = TileTarget(.topHalf).frame(in: rightMonitor.visibleFrame)
        let flipped = ScreenSpace.flipped(top, primaryHeight: primaryHeight)
        #expect(flipped.minY == -133)
        #expect(flipped.height == 707)
    }
}

struct TileDisplayTests {
    @Test func reservingTheBottomRaisesTheVisibleFrame() {
        let display = TileDisplay(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 4, width: 1512, height: 941)
        )
        let reserved = display.reservingBottom(90)
        #expect(reserved.visibleFrame == CGRect(x: 0, y: 90, width: 1512, height: 855))
        #expect(reserved.visibleFrame.maxY == display.visibleFrame.maxY)
        #expect(reserved.frame == display.frame)
    }

    @Test func aSystemDockTallerThanTheReserveWins() {
        #expect(laptop.reservingBottom(30) == laptop)
    }

    @Test func theReserveCountsFromTheBottomOfThatDisplay() {
        let reserved = rightMonitor.reservingBottom(100)
        #expect(reserved.visibleFrame.minY == -200)
        #expect(reserved.visibleFrame.maxY == rightMonitor.visibleFrame.maxY)
    }

    @Test func theReserveNeverGivesANegativeHeight() {
        #expect(laptop.reservingBottom(5000).visibleFrame.height == 0)
    }
}

struct TilePlannerPlacementTests {
    private let planner = TilePlanner(displays: [laptop, rightMonitor, leftMonitor])

    @Test func aWindowBelongsToTheDisplayWithMostOfIt() {
        let straddling = CGRect(x: 1300, y: 100, width: 800, height: 500)
        #expect(planner.display(of: straddling) == rightMonitor)
        let mostlyLaptop = CGRect(x: 1000, y: 100, width: 800, height: 500)
        #expect(planner.display(of: mostlyLaptop) == laptop)
        let onTheLeft = CGRect(x: -700, y: 100, width: 800, height: 500)
        #expect(planner.display(of: onTheLeft) == leftMonitor)
    }

    @Test func aLostWindowCountsAsOnThePrimary() {
        let lost = CGRect(x: 90000, y: 90000, width: 300, height: 300)
        #expect(planner.display(of: lost) == laptop)
    }

    @Test func noDisplaysMeansNoPlan() {
        let empty = TilePlanner(displays: [])
        #expect(empty.display(of: freeWindow) == nil)
        #expect(empty.plan(.place(.leftHalf), window: freeWindow, app: app, memory: nil) == nil)
    }

    @Test func placesOnTheDisplayTheWindowIsOn() throws {
        let window = CGRect(x: 2000, y: 100, width: 800, height: 500)
        let plan = try #require(planner.plan(.place(.leftHalf), window: window, app: app, memory: nil))
        #expect(plan.display == rightMonitor)
        #expect(plan.frame == CGRect(x: 1512, y: -300, width: 1280, height: 1415))
        #expect(plan.tile == TileTarget(.leftHalf))
    }

    @Test func aDisplayLeftOfThePrimaryWorksWithNegativeX() throws {
        let window = CGRect(x: -900, y: 100, width: 300, height: 300)
        let plan = try #require(planner.plan(.place(.topRight), window: window, app: app, memory: nil))
        #expect(plan.frame == CGRect(x: -960, y: 528, width: 960, height: 527))
    }

    @Test func aDockOnTheLeftMovesTheLeftEdge() throws {
        let display = TileDisplay(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 80, y: 0, width: 1432, height: 945)
        )
        let plan = try #require(
            TilePlanner(displays: [display]).plan(.place(.leftHalf), window: freeWindow, app: app, memory: nil)
        )
        #expect(plan.frame == CGRect(x: 80, y: 0, width: 716, height: 945))
    }

    @Test func aDockOnTheRightMovesTheRightEdge() throws {
        let display = TileDisplay(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1432, height: 945)
        )
        let plan = try #require(
            TilePlanner(displays: [display]).plan(.place(.rightHalf), window: freeWindow, app: app, memory: nil)
        )
        #expect(plan.frame.maxX == 1432)
        #expect(plan.frame.minX == 716)
    }

    @Test func aBottomTileStopsAboveTheDock() throws {
        let plan = try #require(planner.plan(.place(.bottomLeft), window: freeWindow, app: app, memory: nil))
        #expect(plan.frame.minY == 70)
    }

    @Test func aTopTileStopsBelowTheMenuBar() throws {
        let plan = try #require(planner.plan(.place(.topLeft), window: freeWindow, app: app, memory: nil))
        #expect(plan.frame.maxY == 945)
    }
}

struct TilePlannerCycleTests {
    private let planner = TilePlanner(displays: [laptop, rightMonitor])
    private let visible = laptop.visibleFrame

    /// Presses a shortcut and lets the window land where `landing` says, as the app does after a real move.
    private func press(
        _ layout: TileLayout,
        window: inout CGRect,
        memory: inout TileMemory?,
        landing: (CGRect) -> CGRect = { $0 }
    ) throws -> TileTarget {
        let plan = try #require(planner.plan(.place(layout), window: window, app: app, memory: memory))
        let tile = try #require(plan.tile)
        window = landing(plan.frame)
        memory = TileMemory(app: app, tile: tile, frame: window)
        return tile
    }

    @Test(arguments: [TileLayout.leftHalf, .rightHalf, .topHalf, .bottomHalf])
    func aHalfGoesThroughThirdsAndBack(layout: TileLayout) throws {
        var window = freeWindow
        var memory: TileMemory?
        let steps = try (0 ..< 4).map { _ in try press(layout, window: &window, memory: &memory).step }
        #expect(steps == [0, 1, 2, 0])
    }

    @Test func theLeftHalfTakesTwoThirdsThenOneThird() throws {
        var window = freeWindow
        var memory: TileMemory?
        _ = try press(.leftHalf, window: &window, memory: &memory)
        #expect(window.width == 756)
        _ = try press(.leftHalf, window: &window, memory: &memory)
        #expect(window.width == 1008)
        #expect(window.minX == 0)
        _ = try press(.leftHalf, window: &window, memory: &memory)
        #expect(window.width == 504)
    }

    @Test func theRightHalfStaysOnTheRightEdge() throws {
        var window = freeWindow
        var memory: TileMemory?
        for _ in 0 ..< 3 {
            _ = try press(.rightHalf, window: &window, memory: &memory)
            #expect(window.maxX == visible.maxX)
        }
    }

    @Test func topAndBottomGoThroughThirdsOfTheHeight() throws {
        var window = freeWindow
        var memory: TileMemory?
        _ = try press(.topHalf, window: &window, memory: &memory)
        _ = try press(.topHalf, window: &window, memory: &memory)
        #expect(window.maxY == visible.maxY)
        #expect(window.height == (visible.height * 2 / 3).rounded())
        #expect(window.width == visible.width)
        _ = try press(.bottomHalf, window: &window, memory: &memory)
        _ = try press(.bottomHalf, window: &window, memory: &memory)
        #expect(window.minY == visible.minY)
        #expect(window.height == (visible.height * 2 / 3).rounded())
    }

    /// Terminal snaps to whole characters, so it never lands on the frame it was given.
    @Test func aWindowThatRoundsItsSizeStillCycles() throws {
        var window = freeWindow
        var memory: TileMemory?
        let snap: (CGRect)
            -> CGRect = { CGRect(x: $0.minX, y: $0.minY + 9, width: $0.width - 7, height: $0.height - 9) }
        let steps = try (0 ..< 4).map { _ in
            try press(.leftHalf, window: &window, memory: &memory, landing: snap).step
        }
        #expect(steps == [0, 1, 2, 0])
    }

    @Test func anotherLayoutStartsFromTheFirstStep() throws {
        var window = freeWindow
        var memory: TileMemory?
        _ = try press(.leftHalf, window: &window, memory: &memory)
        _ = try press(.leftHalf, window: &window, memory: &memory)
        #expect(try press(.rightHalf, window: &window, memory: &memory).step == 0)
    }

    @Test func aWindowMovedByHandStartsAgain() throws {
        var window = freeWindow
        var memory: TileMemory?
        _ = try press(.leftHalf, window: &window, memory: &memory)
        window = window.offsetBy(dx: 40, dy: 0)
        #expect(try press(.leftHalf, window: &window, memory: &memory).step == 0)
    }

    @Test func anotherAppStartsAgainEvenAtTheRememberedFrame() throws {
        let snapped = CGRect(x: 0, y: 79, width: 749, height: 866)
        let memory = TileMemory(app: 7, tile: TileTarget(.leftHalf, step: 1), frame: snapped)
        let plan = try #require(planner.plan(.place(.leftHalf), window: snapped, app: app, memory: memory))
        #expect(plan.tile == TileTarget(.leftHalf))
    }

    /// After a restart nothing is remembered, but a window already sitting on the half is plainly there.
    @Test func aWindowAlreadyOnTheHalfMovesOnWithoutMemory() throws {
        let window = TileTarget(.leftHalf).frame(in: visible)
        let plan = try #require(planner.plan(.place(.leftHalf), window: window, app: app, memory: nil))
        #expect(plan.tile == TileTarget(.leftHalf, step: 1))
    }

    @Test func aLayoutWithOneStepStaysPut() throws {
        var window = freeWindow
        var memory: TileMemory?
        _ = try press(.center, window: &window, memory: &memory)
        let first = window
        #expect(try press(.center, window: &window, memory: &memory).step == 0)
        #expect(window == first)
    }

    @Test func aFirstThirdPressedAsAHalfGoesBackToHalf() throws {
        let window = TileTarget(.firstThird).frame(in: visible)
        let plan = try #require(planner.plan(.place(.leftHalf), window: window, app: app, memory: nil))
        #expect(plan.tile == TileTarget(.leftHalf))
    }
}

struct TilePlannerDisplayTests {
    private let threeInARow = TilePlanner(displays: [laptop, rightMonitor, leftMonitor])

    @Test func oneDisplayHasNowhereToGo() {
        let planner = TilePlanner(displays: [laptop])
        #expect(planner.plan(.nextDisplay, window: freeWindow, app: app, memory: nil) == nil)
        #expect(planner.plan(.previousDisplay, window: freeWindow, app: app, memory: nil) == nil)
    }

    @Test func nextGoesRightAndWrapsAround() throws {
        var window = CGRect(x: -900, y: 100, width: 300, height: 300)
        var visited: [TileDisplay] = []
        for _ in 0 ..< 3 {
            let plan = try #require(threeInARow.plan(.nextDisplay, window: window, app: app, memory: nil))
            visited.append(plan.display)
            window = plan.frame
        }
        #expect(visited == [laptop, rightMonitor, leftMonitor])
    }

    @Test func previousGoesLeftAndWrapsAround() throws {
        var window = CGRect(x: -900, y: 100, width: 300, height: 300)
        var visited: [TileDisplay] = []
        for _ in 0 ..< 3 {
            let plan = try #require(threeInARow.plan(.previousDisplay, window: window, app: app, memory: nil))
            visited.append(plan.display)
            window = plan.frame
        }
        #expect(visited == [rightMonitor, laptop, leftMonitor])
    }

    @Test func orderDoesNotDependOnWhichDisplayIsPrimary() throws {
        let planner = TilePlanner(displays: [rightMonitor, leftMonitor, laptop])
        let plan = try #require(planner.plan(.nextDisplay, window: freeWindow, app: app, memory: nil))
        #expect(plan.display == rightMonitor)
    }

    @Test func stackedDisplaysGoFromTopToBottom() throws {
        let planner = TilePlanner(displays: [laptop, topMonitor])
        let plan = try #require(planner.plan(.nextDisplay, window: freeWindow, app: app, memory: nil))
        #expect(plan.display == topMonitor)
        let top = CGRect(x: 100, y: 1200, width: 300, height: 300)
        let back = try #require(planner.plan(.nextDisplay, window: top, app: app, memory: nil))
        #expect(back.display == laptop)
    }

    @Test func aTiledWindowTakesTheSameTileOnTheNextDisplay() throws {
        let window = TileTarget(.leftHalf).frame(in: laptop.visibleFrame)
        let plan = try #require(threeInARow.plan(.nextDisplay, window: window, app: app, memory: nil))
        #expect(plan.frame == TileTarget(.leftHalf).frame(in: rightMonitor.visibleFrame))
        #expect(plan.tile == TileTarget(.leftHalf))
    }

    @Test func aRememberedStepTravelsAndTheNextPressContinues() throws {
        let snapped = CGRect(x: 0, y: 79, width: 1001, height: 866)
        let memory = TileMemory(app: app, tile: TileTarget(.leftHalf, step: 1), frame: snapped)
        let plan = try #require(threeInARow.plan(.nextDisplay, window: snapped, app: app, memory: memory))
        #expect(plan.tile == TileTarget(.leftHalf, step: 1))
        #expect(plan.frame == TileTarget(.leftHalf, step: 1).frame(in: rightMonitor.visibleFrame))

        let landed = TileMemory(app: app, tile: TileTarget(.leftHalf, step: 1), frame: plan.frame)
        let next = try #require(threeInARow.plan(.place(.leftHalf), window: plan.frame, app: app, memory: landed))
        #expect(next.tile == TileTarget(.leftHalf, step: 2))
        #expect(next.display == rightMonitor)
    }

    @Test func aFreeWindowKeepsItsSizeAndItsPlace() throws {
        let plan = try #require(threeInARow.plan(.nextDisplay, window: freeWindow, app: app, memory: nil))
        #expect(plan.tile == nil)
        #expect(plan.frame.size == freeWindow.size)
        #expect(rightMonitor.visibleFrame.contains(plan.frame))
        let share = (freeWindow.midX - laptop.visibleFrame.minX) / laptop.visibleFrame.width
        let expected = rightMonitor.visibleFrame.minX + share * rightMonitor.visibleFrame.width
        #expect(abs(plan.frame.midX - expected) <= 1)
    }

    @Test func aWindowTooBigForTheSmallerDisplayShrinksToFit() throws {
        let huge = CGRect(x: 1600, y: -250, width: 2400, height: 1300)
        let plan = try #require(
            TilePlanner(displays: [laptop, rightMonitor]).plan(.nextDisplay, window: huge, app: app, memory: nil)
        )
        #expect(plan.display == laptop)
        #expect(plan.frame == laptop.visibleFrame)
    }
}

struct TileSettlingTests {
    private let visible = laptop.visibleFrame

    @Test func aWindowThatFitsStaysWhereItIs() {
        #expect(TilePlanner.settled(freeWindow, in: visible) == freeWindow)
    }

    @Test func aWindowWiderThanItsTileIsPulledBackFromTheRightEdge() {
        let tooWide = CGRect(x: 756, y: 70, width: 900, height: 875)
        #expect(TilePlanner.settled(tooWide, in: visible).maxX > visible.minX)
        let narrower = CGRect(x: 1000, y: 70, width: 600, height: 875)
        #expect(TilePlanner.settled(narrower, in: visible).maxX == visible.maxX)
    }

    @Test func aWindowCannotEndUpBelowTheDock() {
        let low = CGRect(x: 100, y: 0, width: 400, height: 300)
        #expect(TilePlanner.settled(low, in: visible).minY == visible.minY)
    }

    @Test func aWindowTallerThanTheScreenKeepsItsTitleBarOnScreen() {
        let tall = CGRect(x: 100, y: 0, width: 400, height: 2000)
        let settled = TilePlanner.settled(tall, in: visible)
        #expect(settled.maxY == visible.maxY)
        #expect(settled.height == 2000)
    }

    @Test func aWindowWiderThanTheScreenStartsAtItsLeftEdge() {
        let wide = CGRect(x: 300, y: 100, width: 3000, height: 300)
        #expect(TilePlanner.settled(wide, in: visible).minX == visible.minX)
    }
}

struct GlobalShortcutTests {
    @Test func labelsMatchTheDesign() {
        let labels = TileCommand.all.map(\.shortcut.label)
        #expect(labels == [
            "⌃⌥←", "⌃⌥→", "⌃⌥↑", "⌃⌥↓",
            "⌃⌥↩", "⌃⌥C", "⌃⌥D", "⌃⌥G",
            "⌃⌥U", "⌃⌥I", "⌃⌥J", "⌃⌥K",
            "⌃⌥⌘←", "⌃⌥⌘→",
        ])
    }

    @Test func reservedLabelsReadAsInTheApp() {
        #expect(GlobalShortcut.reserved.map(\.label) == ["⌃⌥Space", "⇧⌘V", "⇧⌘2", "⌃⌥Q", "⌃⌥H"])
    }

    @Test func everyTileShortcutIsDifferent() {
        let shortcuts = TileCommand.all.map(\.shortcut)
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    @Test func noTileShortcutTakesOneFromAnotherFeature() {
        let taken = Set(GlobalShortcut.reserved)
        #expect(taken.isDisjoint(with: TileCommand.all.map(\.shortcut)))
    }

    @Test func reservedShortcutsAreDifferentToo() {
        #expect(Set(GlobalShortcut.reserved).count == GlobalShortcut.reserved.count)
    }
}

@MainActor
struct WindowTilesSettingsTests {
    @Test func offByDefaultWithThePreviewOn() {
        let settings = AppSettings().windowTiles
        #expect(!settings.isEnabled)
        #expect(settings.showsPreview)
    }

    @Test func anOlderFileLeavesTheModuleOff() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.windowTiles == WindowTilesSettings())
    }

    @Test func roundTripsThroughTheFile() throws {
        let file = SettingsFile(url: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkTiles-\(UUID().uuidString)/settings.json"))
        var settings = AppSettings()
        settings.windowTiles.isEnabled = true
        settings.windowTiles.showsPreview = false

        try file.save(settings)

        #expect(try file.load() == settings)
    }

    @Test func oneKeyByHandKeepsTheOtherDefault() throws {
        let json = #"{"windowTiles": {"isEnabled": true}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.windowTiles.isEnabled)
        #expect(settings.windowTiles.showsPreview)
    }

    @Test func aBrokenSectionCostsOnlyThatSection() throws {
        let json = #"{"numberStyle": "precise", "windowTiles": {"isEnabled": "yes"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.numberStyle == .precise)
        #expect(!settings.windowTiles.isEnabled)
    }
}
