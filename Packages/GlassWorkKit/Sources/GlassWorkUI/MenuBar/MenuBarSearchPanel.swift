import AppKit
import GlassWorkCore
import Observation
import SwiftUI

/// What a key does in the menu bar search. Read before the text field, which would keep the arrows.
public enum MenuBarSearchKey: Equatable, Sendable {
    case activate, previous, next

    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let downArrow: UInt16 = 125
    private static let upArrow: UInt16 = 126

    public init?(keyCode: UInt16) {
        switch keyCode {
        case Self.returnKey, Self.keypadEnter: self = .activate
        case Self.upArrow: self = .previous
        case Self.downArrow: self = .next
        default: return nil
        }
    }
}

/// The search over other apps' menu bar items: the list, the query and the highlighted row.
@MainActor
@Observable
public final class MenuBarSearchState {
    public enum Phase: Equatable, Sendable {
        /// Accessibility is not granted, so the other apps' items cannot be read.
        case needsAccess
        case loading
        case ready
    }

    public var query = "" {
        didSet {
            if query != oldValue {
                selection = nil
            }
        }
    }

    /// Off: only the hidden items. On: every item in the bar.
    public var showsAll = false {
        didSet {
            if showsAll != oldValue {
                selection = nil
            }
        }
    }

    public private(set) var phase: Phase
    public private(set) var selection: String?
    private var entries: [MenuBarEntry] = []
    private var separatorMaxX: Double?
    private var alwaysHiddenMaxX: Double?
    @ObservationIgnored private let onActivate: (MenuBarEntry) -> Void
    @ObservationIgnored private let onOpenSettings: () -> Void
    @ObservationIgnored fileprivate let icon: (MenuBarEntry) -> NSImage?

    private static let limit = 8

    public init(
        phase: Phase = .loading,
        query: String = "",
        showsAll: Bool = false,
        icon: @escaping (MenuBarEntry) -> NSImage? = { _ in nil },
        onActivate: @escaping (MenuBarEntry) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.phase = phase
        self.query = query
        self.showsAll = showsAll
        self.icon = icon
        self.onActivate = onActivate
        self.onOpenSettings = onOpenSettings
    }

    /// The inventory has been read. The separator positions are where they are now, not when the panel opened.
    public func load(_ entries: [MenuBarEntry], separatorMaxX: Double?, alwaysHiddenMaxX: Double?) {
        self.entries = entries
        self.separatorMaxX = separatorMaxX
        self.alwaysHiddenMaxX = alwaysHiddenMaxX
        phase = .ready
    }

    public func requireAccess() {
        phase = .needsAccess
    }

    public var results: [MenuBarEntry] {
        let candidates = MenuBarSearch.candidates(
            entries,
            separatorMaxX: separatorMaxX,
            alwaysHiddenMaxX: alwaysHiddenMaxX,
            showAll: showsAll
        )
        return Array(MenuBarSearch.results(candidates, query: query).prefix(Self.limit))
    }

    /// The first row until the arrows choose another.
    public var highlighted: MenuBarEntry? {
        let rows = results
        return rows.first { $0.id == selection } ?? rows.first
    }

    public func section(of entry: MenuBarEntry) -> MenuBarSection {
        MenuBarSearch.section(of: entry, separatorMaxX: separatorMaxX, alwaysHiddenMaxX: alwaysHiddenMaxX)
    }

    public func handle(_ key: MenuBarSearchKey) {
        switch key {
        case .previous: move(-1)
        case .next: move(1)
        case .activate: activate()
        }
    }

    public func activate() {
        guard phase == .ready, let highlighted else { return }
        onActivate(highlighted)
    }

    /// A click on a row.
    public func choose(_ entry: MenuBarEntry) {
        guard phase == .ready else { return }
        onActivate(entry)
    }

    public func openSettings() {
        onOpenSettings()
    }

    private func move(_ step: Int) {
        let rows = results
        guard let current = rows.firstIndex(where: { $0.id == highlighted?.id }) else { return }
        selection = rows[min(max(current + step, 0), rows.count - 1)].id
    }
}

/// Find a menu bar item by name and open it without touching the mouse.
public struct MenuBarSearchView: View {
    @Bindable private var state: MenuBarSearchState
    @FocusState private var isFocused: Bool

    public init(state: MenuBarSearchState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.phase == .needsAccess {
                access
            } else {
                search
            }
        }
        .padding(10)
        .frame(width: 520)
        .onAppear { isFocused = true }
    }

    private var access: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(
                loc(
                    "Searching menu bar items needs Accessibility access to read what other apps put there."
                )
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Button(loc("Open Accessibility Settings")) { state.openSettings() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var search: some View {
        TextField(loc("Type an item or app name"), text: $state.query)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($isFocused)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
        let rows = state.results
        if state.phase == .loading {
            message(loc("Reading menu bar items…"))
        } else if rows.isEmpty {
            message(emptyText)
        }
        ForEach(rows) { row($0) }
        HStack {
            Text(loc("Return opens  ·  ↑↓ choose  ·  Esc closes"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(loc("Show all"), isOn: $state.showsAll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
        }
        .padding(.top, 2)
    }

    private var emptyText: String {
        if !state.query.isEmpty {
            return loc("No matches")
        }
        return state.showsAll ? loc("No menu bar items found") : loc("No hidden items")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private func row(_ entry: MenuBarEntry) -> some View {
        let isSelected = entry.id == state.highlighted?.id
        let section = state.section(of: entry)
        return Button {
            state.choose(entry)
        } label: {
            HStack(spacing: 10) {
                Glyph(entry: entry, image: state.icon(entry))
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                if entry.name != entry.appName {
                    Text(entry.appName)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if section != .visible {
                    Text(section == .alwaysHidden ? loc("Always hidden") : loc("Hidden"))
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(isSelected ? Palette.blue : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The owning app's icon, or its first letter when it has none.
    private struct Glyph: View {
        let entry: MenuBarEntry
        let image: NSImage?

        private static let tints = [
            Palette.blue, Palette.teal, Palette.purple, Palette.green, Palette.red, Palette.orange, Palette.pink,
        ]

        var body: some View {
            if let image {
                Image(nsImage: image).resizable().frame(width: 22, height: 22)
            } else {
                let sum = entry.appName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
                Text(entry.appName.prefix(1).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Self.tints[sum % Self.tints.count].gradient, in: .rect(cornerRadius: 5.5))
            }
        }
    }
}
