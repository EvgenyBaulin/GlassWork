import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// The clocks, focus tools and daily facts with data, in both appearances. Views read only the date they are given,
/// so these stay stable between runs. Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct TimeWidgetSnapshotTests {
    private static let now = Date(timeIntervalSince1970: 1_793_750_000)

    nonisolated static let kinds: [WidgetKind] = [.clock, .numeralsClock, .minimalClock, .flipClock]

    private var sample: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: Self.now)
        snapshot.everyday.cities = [
            WorldCity(name: "London", timeZone: "Europe/London"),
            WorldCity(name: "Tokyo", timeZone: "Asia/Tokyo"),
            WorldCity(name: "New York", timeZone: "America/New_York"),
            WorldCity(name: "Sydney", timeZone: "Australia/Sydney"),
            WorldCity(name: "Dubai", timeZone: "Asia/Dubai"),
            WorldCity(name: "Lima", timeZone: "America/Lima"),
        ]
        snapshot.place = WeatherPlace(id: 1, name: "Moscow", country: "Russia", latitude: 55.75, longitude: 37.62)
        return snapshot
    }

    private func render(_ kind: WidgetKind, _ size: WidgetSize, dark: Bool) {
        let view = WidgetFace(kind: kind, size: size, snapshot: sample, now: Self.now)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(dark ? Color(red: 0.13, green: 0.12, blue: 0.19) : Color(white: 0.96))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let name = "\(kind.rawValue)-\(size.rawValue)-\(dark ? "dark" : "light")"
        assertSnapshot(of: host, as: .image(precision: 0.98), named: name)
    }

    @Test(arguments: kinds)
    func darkEverySize(kind: WidgetKind) {
        for size in WidgetSize.allCases {
            render(kind, size, dark: true)
        }
    }

    @Test(arguments: kinds)
    func lightEverySize(kind: WidgetKind) {
        for size in WidgetSize.allCases {
            render(kind, size, dark: false)
        }
    }
}
