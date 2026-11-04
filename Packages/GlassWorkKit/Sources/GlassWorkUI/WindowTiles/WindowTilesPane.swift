import GlassWorkCore
import SwiftUI

/// The twelve layouts with their shortcuts. Everything it shows comes in from outside, so it does not care
/// which window it is placed in.
public struct WindowTilesPane: View {
    @Binding private var isEnabled: Bool
    @Binding private var showsPreview: Bool
    private let isTrusted: Bool
    /// Shortcuts another app got to first, which therefore do nothing here.
    private let takenShortcuts: [String]
    private let shortcuts: ShortcutSettings
    private let openAccessibilitySettings: () -> Void

    public init(
        isEnabled: Binding<Bool>,
        showsPreview: Binding<Bool>,
        isTrusted: Bool,
        takenShortcuts: [String] = [],
        shortcuts: ShortcutSettings = ShortcutSettings(),
        openAccessibilitySettings: @escaping () -> Void
    ) {
        _isEnabled = isEnabled
        _showsPreview = showsPreview
        self.isTrusted = isTrusted
        self.takenShortcuts = takenShortcuts
        self.shortcuts = shortcuts
        self.openAccessibilitySettings = openAccessibilitySettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isEnabled, !isTrusted {
                    accessibilityBanner
                }
                if isEnabled, !takenShortcuts.isEmpty {
                    takenBanner
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(TileLayout.allCases, id: \.self) { layout in
                        TileCard(layout: layout, shortcut: label(.place(layout)))
                    }
                }
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().padding(.vertical, 4)
                Toggle(loc("Show a short preview"), isOn: $showsPreview)
                    .font(.system(size: 13))
                Text(loc("A short preview shows where the window goes. Turning it off moves the window straight away."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc("Move windows from the keyboard"))
                    .font(.system(size: 14, weight: .semibold))
                Text(loc("Sends the front window to a place on the screen. Needs Accessibility."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(loc("Use Window Tiles"), isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var accessibilityBanner: some View {
        PanelBanner(
            symbol: "lock.shield",
            title: loc("GlassWork needs Accessibility"),
            message: loc("""
            Turn on GlassWork in Privacy & Security → Accessibility. \
            If it is not in the list, press + and add it from Applications.
            """),
            actionTitle: loc("Open System Settings"),
            action: openAccessibilitySettings
        )
    }

    private var takenBanner: some View {
        PanelBanner(
            symbol: "keyboard",
            title: loc("Some shortcuts are taken"),
            message: loc("Another app already uses \(takenShortcuts.joined(separator: ", ")).")
        )
    }

    private var footnote: String {
        let previous = label(.previousDisplay)
        let next = label(.nextDisplay)
        return loc(
            "Press a half again to move through thirds. \(previous) and \(next) send a window to another display."
        )
    }
}

private extension WindowTilesPane {
    /// A dash for a shortcut the user cleared.
    func label(_ command: TileCommand) -> String {
        shortcuts.shortcut(for: .tile(command))?.label ?? "—"
    }
}

/// One layout: a small screen with the place filled in, its name and its shortcut.
private struct TileCard: View {
    let layout: TileLayout
    let shortcut: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TileThumbnail(region: layout.region())
            HStack(spacing: 6) {
                Text(layout.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text(verbatim: shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10))
    }
}

/// Drawn from the same shares the windows use, so the picture cannot disagree with what happens.
private struct TileThumbnail: View {
    let region: TileRegion

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4)
                .fill(Palette.blue.opacity(0.85))
                .frame(
                    width: (region.right - region.left) * proxy.size.width,
                    height: (region.bottom - region.top) * proxy.size.height
                )
                .offset(x: region.left * proxy.size.width, y: region.top * proxy.size.height)
        }
        .frame(height: 70)
        .background(Color.primary.opacity(0.08))
        .clipShape(.rect(cornerRadius: 5))
    }
}
