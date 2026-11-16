import Foundation
@testable import GlassWorkCore
import Testing

struct IslandGeometryTests {
    @Test(arguments: [(1512.0, 982.0, 184.0, 32.0), (1800, 1169, 160, 28), (1312, 850, 216, 38)])
    func displayScaling(width: Double, height: Double, notchWidth: Double, notchHeight: Double) {
        let width = CGFloat(width)
        let height = CGFloat(height)
        let notchWidth = CGFloat(notchWidth)
        let notchHeight = CGFloat(notchHeight)
        let geometry = IslandGeometry(screen: IslandScreen(
            frame: CGRect(x: 0, y: 0, width: width, height: height), safeAreaTop: notchHeight,
            auxiliaryLeftWidth: (width - notchWidth) / 2, auxiliaryRightWidth: (width - notchWidth) / 2,
            menuBarHeight: notchHeight
        ))
        #expect(geometry.hasNotch)
        #expect(geometry.notch.width == notchWidth)
        #expect(geometry.notch.height == notchHeight)
        #expect(geometry.notch.midX == width / 2)
        #expect(geometry.notch.maxY == height)
        #expect(geometry.peekFrame.width == notchWidth + 12)
        #expect(geometry.peekFrame.height == notchHeight + 4)
        #expect(geometry.peekFrame.maxY == height)
        let compact = geometry.compactFrame(leftWing: 90, rightWing: 60)
        #expect(compact.minX == geometry.notch.minX - 90)
        #expect(compact.maxX == geometry.notch.maxX + 60)
        #expect(compact.height == notchHeight)
        #expect(compact.maxY == height)
        let expanded = geometry.expandedFrame(size: CGSize(width: 400, height: 240))
        #expect(expanded.midX == geometry.notch.midX)
        #expect(expanded.maxY == height)
        #expect(expanded.size == CGSize(width: 400, height: 240))
    }

    @Test func virtualNotchUsesMenuBarAndScreenOrigin() {
        let geometry = IslandGeometry(screen: IslandScreen(
            frame: CGRect(x: -1920, y: 982, width: 1920, height: 1080), safeAreaTop: 0, menuBarHeight: 24
        ))
        #expect(!geometry.hasNotch)
        #expect(geometry.notch == CGRect(x: -960, y: 2038, width: 0, height: 24))
        #expect(geometry.peekFrame.maxY == 2062)
        #expect(geometry.compactFrame(leftWing: 50, rightWing: 50).maxY == 2062)
        #expect(geometry.expandedFrame(size: CGSize(width: 300, height: 200)).maxY == 2062)
    }

    @Test(arguments: [
        (500.0, 120.0, false, false),
        (620, 32, true, true),
        (650, 0, false, true),
        (664, 0, false, true),
        (700, 0, false, true)
    ])
    func crowdedMenus(menuEnd: Double, left: Double, iconOnly: Bool, movesLabel: Bool) {
        let left = CGFloat(left)
        let wings = IslandGeometry.wings(
            appMenuMaxX: menuEnd, statusItemsMinX: 900,
            notch: CGRect(x: 664, y: 950, width: 184, height: 32), wanted: 120, wanted: 100, iconOnly: 32
        )
        #expect(wings.left == left)
        #expect(wings.right == 52)
        #expect(wings.isLeftIconOnly == iconOnly)
        #expect(wings.movesLabelRight == movesLabel)
    }

    @Test func clampsWingsAtExactBoundaries() {
        let notch = CGRect(x: 664, y: 950, width: 184, height: 32)
        let wings = IslandGeometry.wings(
            appMenuMaxX: 632, statusItemsMinX: 848, notch: notch, wanted: 100, wanted: 100, iconOnly: 32
        )
        #expect(wings.left == 32)
        #expect(wings.right == 0)
        let clear = IslandGeometry.wings(
            appMenuMaxX: 564, statusItemsMinX: 1000, notch: notch, wanted: 100, wanted: 80, iconOnly: 32
        )
        #expect(clear.left == 100)
        #expect(clear.right == 80)
        #expect(!clear.movesLabelRight)
    }
}
