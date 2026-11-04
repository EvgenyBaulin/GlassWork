import AppKit
import GlassWorkCore
import SwiftUI

/// Icons of running apps, asked for once. The workspace answers from its own cache, so an app in a protected folder
/// raises no prompt the way opening its bundle would.
@MainActor
private enum RunningAppIcons {
    private static var cache: [AppUsage.ID: NSImage?] = [:]

    static func icon(for app: AppUsage) -> NSImage? {
        if let icon = cache[app.id] {
            return icon
        }
        let icon = NSRunningApplication(processIdentifier: app.pid)?.icon
        cache[app.id] = icon
        return icon
    }
}

/// The app's icon, or its first letter for one that has none.
struct AppGlyph: View {
    let app: AppUsage
    let size: CGFloat

    private static let tints = [
        Palette.blue, Palette.teal, Palette.purple, Palette.green, Palette.red, Palette.orange, Palette.pink,
    ]

    private var tint: Color {
        let sum = app.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.tints[sum % Self.tints.count]
    }

    var body: some View {
        if let icon = RunningAppIcons.icon(for: app) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Text(app.name.prefix(1).uppercased())
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint.gradient, in: .rect(cornerRadius: size / 4))
        }
    }
}

/// The red button on the row under the pointer. ⌥ turns it into Force Quit.
struct QuitCapsule: View {
    let app: AppUsage
    var startsForced = false
    @State private var isForced: Bool?
    @Environment(\.panelActions) private var actions

    var body: some View {
        Button {
            // The key as it is now: the label only follows it while one of the app's windows is in front.
            actions.quit(app.target, NSEvent.modifierFlags.contains(.option))
        } label: {
            Text(isForced ?? startsForced ? loc("Force Quit") : loc("Quit"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Palette.red, in: .rect(cornerRadius: 6))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onModifierKeysChanged(mask: .option, initial: !startsForced) { _, keys in
            isForced = keys.contains(.option)
        }
    }
}

/// One app in the Hub or a panel: icon, name and figure, with Quit under the pointer.
struct AppQuitRow: View {
    let app: AppUsage
    let value: String
    var startsHovered = false
    var startsForced = false
    @State private var isHovered: Bool?

    private var showsQuit: Bool {
        (isHovered ?? startsHovered) && !app.isProtected
    }

    var body: some View {
        HStack(spacing: 10) {
            AppGlyph(app: app, size: 22)
            Text(app.name).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if showsQuit {
                QuitCapsule(app: app, startsForced: startsForced)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(
            (isHovered ?? startsHovered) ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 8)
        )
        .contentShape(.rect)
        .onHover { isHovered = $0 }
    }
}

/// The heaviest apps, with Quit on the one under the pointer.
///
/// The order holds still while the pointer is over the list: a row moving away just as the button is clicked would
/// quit the wrong app.
struct TopApps: View {
    let apps: [AppUsage]
    let sort: AppUsageSort
    var limit = 5
    var hoveredID: AppUsage.ID?
    var startsForced = false
    @State private var held: [AppUsage.ID]?

    private var rows: [AppUsage] {
        let sorted = apps.sorted(by: sort)
        return Array((held.map { sorted.arranged(following: $0) } ?? sorted).prefix(limit))
    }

    private func value(_ app: AppUsage) -> String {
        switch sort {
        case .cpu: Format.corePercent(app.cpu)
        case .memory: Format.size(Double(app.memory))
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(rows) { app in
                AppQuitRow(
                    app: app,
                    value: value(app),
                    startsHovered: app.id == hoveredID,
                    startsForced: startsForced
                )
            }
        }
        .onHover { held = $0 ? rows.map(\.id) : nil }
    }
}

/// The Hub's list of apps, the first thing to reach for when the Mac feels slow.
struct RunningAppsBlock: View {
    let apps: [AppUsage]
    var hoveredID: AppUsage.ID?
    var startsForced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Running apps")).font(.system(size: 13, weight: .semibold))
            TopApps(apps: apps, sort: .memory, hoveredID: hoveredID, startsForced: startsForced)
            Text(loc("Hover an app to quit it. ⌥ makes it Force Quit."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
