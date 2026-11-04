import SwiftUI

/// The zone a window is about to fill, with the label in its middle. Fills the window it is put in.
public struct WindowTilesPreview: View {
    private let title: String
    private let shortcut: String

    public init(title: String, shortcut: String) {
        self.title = title
        self.shortcut = shortcut
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.blue.opacity(0.22))
                .strokeBorder(Palette.blue.opacity(0.8), lineWidth: 2)
            WindowTilesLabel(title: title, shortcut: shortcut)
        }
        .padding(4)
    }
}

/// The small label: what the shortcut does, and the shortcut.
struct WindowTilesLabel: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let shortcut: String

    private var tint: Color {
        scheme == .dark ? Color(red: 0.11, green: 0.10, blue: 0.165).opacity(0.55) : .white.opacity(0.7)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(verbatim: shortcut)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(tint, in: .rect(cornerRadius: 12))
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
    }
}

/// What a shortcut has to say when it could not move anything.
public struct WindowTilesNoticeHUD: View {
    private let notice: WindowTilesNotice

    public init(notice: WindowTilesNotice) {
        self.notice = notice
    }

    public var body: some View {
        NoticeHUD(symbol: notice.symbol, title: notice.title, detail: notice.detail)
    }
}
