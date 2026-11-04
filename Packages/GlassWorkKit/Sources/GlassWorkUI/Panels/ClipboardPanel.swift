import AppKit
import GlassWorkCore
import ImageIO
import SwiftUI

extension ClipboardKind {
    var filterTitle: String {
        switch self {
        case .text: loc("Text")
        case .link: loc("Links")
        case .image: loc("Images")
        case .file: loc("Files")
        case .color: loc("Colours")
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }
}

/// Square at the start of a row: an image, a color swatch or a type glyph.
struct ClipboardIcon: View {
    let entry: ClipboardEntry
    let imageURL: URL?
    var isSelected = false
    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
            } else if entry.kind == .color, let color = Color(hexText: entry.text) {
                color
            } else {
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(glyphColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.08))
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(.rect(cornerRadius: 7))
        .task(id: imageURL) { thumbnail = await Self.load(imageURL, size: 56) }
    }

    private var glyphColor: Color {
        if isSelected {
            return .white
        }
        return entry.kind == .link ? Palette.blue : .secondary
    }

    /// Reads only a small version, so a long list of screenshots stays cheap.
    static func load(_ url: URL?, size: Int) async -> CGImage? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}

extension Color {
    /// Reads `#RGB`, `#RRGGBB` and `#RRGGBBAA`.
    init?(hexText: String) {
        var digits = String(hexText.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst())
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let shift = digits.count == 8 ? 8 : 0
        self.init(
            red: Double((value >> (16 + shift)) & 0xFF) / 255,
            green: Double((value >> (8 + shift)) & 0xFF) / 255,
            blue: Double((value >> shift) & 0xFF) / 255,
            opacity: digits.count == 8 ? Double(value & 0xFF) / 255 : 1
        )
    }
}

/// Second line of a row: where it came from, when, and how big for images and files.
func clipboardCaption(_ entry: ClipboardEntry, now: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    var parts = [entry.appName, formatter.localizedString(for: entry.date, relativeTo: now)].compactMap(\.self)
    if entry.kind == .image {
        parts.append(Format.bytes(Double(entry.byteCount), style: .precise))
    }
    return parts.joined(separator: " · ")
}

/// The title with what was searched for marked, as in the design.
func clipboardHighlighted(_ text: String, query: String) -> AttributedString {
    var result = AttributedString(text)
    guard !query.isEmpty else { return result }
    var start = result.startIndex
    while let range = result[start...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
        result[range].backgroundColor = Palette.orange.opacity(0.45)
        start = range.upperBound
    }
    return result
}

/// One entry. Click uses it, and the buttons on hover pin or delete it.
struct ClipboardRow: View {
    let entry: ClipboardEntry
    let imageURL: URL?
    var query = ""
    var shortcut: Int?
    var isHovered = false
    let now: Date
    let onUse: (Bool) -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onUse(NSEvent.modifierFlags.contains(.option))
            } label: {
                label
            }
            .buttonStyle(.plain)
            .modifier(NumberShortcut(number: shortcut))
            trailing
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(isHovered ? .white.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
    }

    private var label: some View {
        HStack(spacing: 10) {
            ClipboardIcon(entry: entry, imageURL: imageURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(clipboardHighlighted(title, query: query))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(clipboardCaption(entry, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    private var title: String {
        entry.kind == .image ? loc("Image · \(entry.title)") : entry.title
    }

    @ViewBuilder
    private var trailing: some View {
        if isHovered {
            Button(action: onPin) {
                Image(systemName: entry.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(entry.isPinned ? loc("Unpin") : loc("Pin"))
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(loc("Delete"))
        } else if entry.isPinned {
            Image(systemName: "pin.fill").foregroundStyle(Palette.yellow).font(.system(size: 11))
        } else if let shortcut {
            Text("⌘\(shortcut)").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}

/// ⌘1 to ⌘9 use the first recent entries.
private struct NumberShortcut: ViewModifier {
    let number: Int?

    func body(content: Content) -> some View {
        if let number, let digit = "\(number)".first {
            content.keyboardShortcut(KeyEquivalent(digit), modifiers: .command)
        } else {
            content
        }
    }
}

/// The history: search, type filter, pinned entries first, then the rest, newest on top.
struct ClipboardPanel: View {
    let store: ClipboardStore
    var now: Date?
    @State private var query = ""
    @State private var kind: ClipboardKind?
    @State private var hovered: ClipboardEntry.ID?
    @State private var isConfirmingClear = false
    @Environment(\.panelActions) private var actions

    private static let rowHeight: CGFloat = 43
    private static let headerHeight: CGFloat = 20
    private static let listLimit: CGFloat = 330

    private var matches: [ClipboardEntry] {
        store.history.matching(query, kind: kind)
    }

    private var isFiltering: Bool {
        !query.isEmpty || kind != nil
    }

    var body: some View {
        PanelFrame(
            module: .clipboard,
            subtitle: subtitle,
            footerTitle: store.history.recent.isEmpty ? nil : loc("Clear all"),
            footerAction: { isConfirmingClear = true }
        ) {
            if !store.settings.isRecording {
                recordingOff
            }
            if store.isAccessDenied {
                PanelBanner(
                    symbol: "hand.raised",
                    title: loc("Pasteboard access is denied"),
                    message: loc("Allow GlassWork in System Settings to keep a history.")
                )
            }
            if store.settings.pasteOnClick, !actions.isPasteAllowed() {
                PanelBanner(
                    symbol: "lock",
                    title: loc("Allow pasting"),
                    message: loc("GlassWork needs Accessibility to paste. Until then, a click only copies."),
                    actionTitle: loc("Settings…"),
                    action: { actions.openSettings(.clipboard) }
                )
            }
            if store.history.entries.isEmpty {
                empty
            } else {
                filters
                list
                Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .confirmationDialog(loc("Clear the history?"), isPresented: $isConfirmingClear) {
            Button(loc("Clear all"), role: .destructive) { store.clearAll() }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("Pinned items stay."))
        }
    }

    private var subtitle: String {
        let total = store.history.entries.count
        return isFiltering ? loc("\(matches.count) of \(total)") : loc("\(total) items")
    }

    private var hint: String {
        store.settings.pasteOnClick && actions.isPasteAllowed()
            ? loc("Click to paste · ⌥-click pastes plain text")
            : loc("Click to copy")
    }

    /// The first read makes macOS show its pasteboard alert, so it waits for this button.
    private var recordingOff: some View {
        PanelBanner(
            symbol: "pause.circle",
            tint: Palette.teal,
            title: loc("History is off"),
            message: loc("macOS will ask to allow pasteboard access. Passwords are never saved."),
            actionTitle: loc("Start"),
            action: { actions.updateSettings { $0.clipboard.isRecording = true } }
        )
    }

    private var empty: some View {
        PanelEmptyState(
            symbol: "list.clipboard",
            title: loc("Nothing copied yet"),
            message: loc("Copy text, a link, an image or a file and it appears here. Passwords are never saved.")
        ) {
            Text(loc("Keeps up to 500 items for \(store.settings.retentionDays) days"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            TextField(loc("Search"), text: $query).textFieldStyle(.roundedBorder)
            HStack(spacing: 4) {
                chip(loc("All"), nil)
                ForEach(ClipboardKind.allCases, id: \.self) { chip($0.filterTitle, $0) }
            }
        }
    }

    private func chip(_ title: String, _ value: ClipboardKind?) -> some View {
        Button {
            kind = value
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(kind == value ? Palette.blue : .white.opacity(0.08), in: Capsule())
                .foregroundStyle(kind == value ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var list: some View {
        let entries = matches
        if entries.isEmpty {
            Text(loc("No matches")).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 20)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    section(loc("Pinned"), entries.filter(\.isPinned), numbered: false)
                    section(loc("Recent"), entries.filter { !$0.isPinned }, numbered: true)
                }
            }
            .frame(height: min(listHeight(entries), Self.listLimit))
            .overlay(alignment: .bottom) { preview }
        }
    }

    private func listHeight(_ entries: [ClipboardEntry]) -> CGFloat {
        let sections = Set(entries.map(\.isPinned)).count
        return CGFloat(entries.count) * Self.rowHeight + CGFloat(sections) * Self.headerHeight
    }

    @ViewBuilder
    private func section(_ title: String, _ entries: [ClipboardEntry], numbered: Bool) -> some View {
        if !entries.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ClipboardRow(
                    entry: entry,
                    imageURL: store.imageURL(for: entry),
                    query: query,
                    shortcut: numbered && index < 9 ? index + 1 : nil,
                    isHovered: hovered == entry.id,
                    now: now ?? Date(),
                    onUse: { actions.useClipboardEntry(entry, $0) },
                    onPin: { store.togglePin(entry) },
                    onDelete: { store.delete(entry) }
                )
                .onHover { hovered = $0 ? entry.id : hovered == entry.id ? nil : hovered }
            }
        }
    }

    /// Stays inside the panel, so it cannot cover the app underneath or take the cursor away from the row.
    @ViewBuilder
    private var preview: some View {
        if let entry = store.history.entries.first(where: { $0.id == hovered && $0.kind == .image }) {
            ClipboardPreview(entry: entry, url: store.imageURL(for: entry))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// Larger picture of a hovered image, with its size.
struct ClipboardPreview: View {
    let entry: ClipboardEntry
    let url: URL?
    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 130)
                    .clipShape(.rect(cornerRadius: 6))
            }
            Text("\(entry.title) · \(Format.bytes(Double(entry.byteCount), style: .precise))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .task(id: url) { image = await ClipboardIcon.load(url, size: 520) }
    }
}

/// Compact history opened by ⇧⌘V: type to filter, arrows and Return or a digit to use an entry.
public struct QuickPasteView: View {
    private let store: ClipboardStore
    private let now: Date?
    private let onUse: (ClipboardEntry) -> Void
    private let onCancel: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    private static let limit = 9

    public init(
        store: ClipboardStore,
        now: Date? = nil,
        onUse: @escaping (ClipboardEntry) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.store = store
        self.now = now
        self.onUse = onUse
        self.onCancel = onCancel
    }

    private var entries: [ClipboardEntry] {
        Array(store.history.matching(query, kind: nil).prefix(Self.limit))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(loc("Type to filter…"), text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onChange(of: query) { selection = 0 }
                .onSubmit { _ = use(selection) }
                .onExitCommand(perform: onCancel)
                // On the field itself: it has the focus, and would otherwise keep these keys for its text.
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(characters: .decimalDigits) { press in
                    // Digits filter once something was typed, so a search for "404" still works.
                    guard query.isEmpty, let digit = Int(press.characters), digit > 0 else { return .ignored }
                    return use(digit - 1)
                }
            if entries.isEmpty {
                Text(store.history.entries.isEmpty ? loc("Nothing copied yet") : loc("No matches"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry, index: index)
            }
            Text(loc("↑↓ select · ↩ paste · 1–9 · esc"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .frame(width: 300)
        .onAppear { isFocused = true }
    }

    private func row(_ entry: ClipboardEntry, index: Int) -> some View {
        Button {
            onUse(entry)
        } label: {
            HStack(spacing: 8) {
                ClipboardIcon(entry: entry, imageURL: store.imageURL(for: entry), isSelected: index == selection)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.kind == .image ? loc("Image · \(entry.title)") : entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(clipboardCaption(entry, now: now ?? Date()))
                        .font(.system(size: 11))
                        .opacity(0.7)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(index + 1)").font(.system(size: 11)).opacity(0.6)
            }
            .padding(5)
            .background(index == selection ? Palette.blue : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !entries.isEmpty else { return .ignored }
        selection = min(max(selection + step, 0), entries.count - 1)
        return .handled
    }

    private func use(_ index: Int) -> KeyPress.Result {
        guard entries.indices.contains(index) else { return .ignored }
        onUse(entries[index])
        return .handled
    }
}
