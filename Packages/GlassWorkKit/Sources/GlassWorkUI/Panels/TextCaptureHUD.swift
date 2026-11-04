import SwiftUI

/// What ⇧⌘2 has to say when it is done.
public enum TextCaptureNotice: Equatable, Sendable {
    case copied(characters: Int)
    case noText
    case needsScreenRecording

    /// Instructions need time to be read.
    public var duration: Duration {
        self == .needsScreenRecording ? .seconds(7) : .seconds(2)
    }

    var symbol: String {
        switch self {
        case .copied: "text.viewfinder"
        case .noText: "text.magnifyingglass"
        case .needsScreenRecording: "lock.shield"
        }
    }

    var title: String {
        switch self {
        case let .copied(characters): loc("\(characters) characters copied")
        case .noText: loc("No text found")
        case .needsScreenRecording: loc("GlassWork needs Screen Recording")
        }
    }

    var detail: String? {
        guard self == .needsScreenRecording else { return nil }
        return loc("""
        Add GlassWork in System Settings → Privacy & Security → Screen & System Audio Recording, \
        then press ⇧⌘2 again.
        """)
    }
}

/// The small message that appears after a text capture.
public struct TextCaptureHUD: View {
    private let notice: TextCaptureNotice

    public init(notice: TextCaptureNotice) {
        self.notice = notice
    }

    public var body: some View {
        NoticeHUD(symbol: notice.symbol, title: notice.title, detail: notice.detail)
    }
}

/// A short message low on the screen, with room for instructions when there are any.
struct NoticeHUD: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: detail == nil ? nil : 340, alignment: .leading)
    }
}
