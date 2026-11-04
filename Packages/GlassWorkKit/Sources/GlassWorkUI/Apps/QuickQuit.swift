import AppKit
import GlassWorkCore
import Observation
import SwiftUI

/// What a key does in the palette. Return with ⌥ never reaches a text field's submit action, because the field takes
/// it for a line break, so the keys are read before the field sees them.
public enum QuickQuitKey: Equatable, Sendable {
    case quit, forceQuit, previous, next

    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let downArrow: UInt16 = 125
    private static let upArrow: UInt16 = 126

    public init?(keyCode: UInt16, isOptionDown: Bool) {
        switch keyCode {
        case Self.returnKey, Self.keypadEnter: self = isOptionDown ? .forceQuit : .quit
        case Self.upArrow: self = .previous
        case Self.downArrow: self = .next
        default: return nil
        }
    }
}

/// The palette's search and highlighted row. System apps and GlassWork are not offered at all.
@MainActor
@Observable
public final class QuickQuitState {
    public var query = "" {
        didSet {
            if query != oldValue {
                selection = nil
            }
        }
    }

    public private(set) var selection: AppUsage.ID?
    private let store: AppUsageStore
    /// Figures keep updating under the palette, but rows must not trade places just as Return is pressed.
    private let order: [AppUsage.ID]
    @ObservationIgnored private let onQuit: (AppUsage, Bool) -> Void

    private static let limit = 6

    public init(store: AppUsageStore, query: String = "", onQuit: @escaping (AppUsage, Bool) -> Void) {
        self.store = store
        self.query = query
        self.onQuit = onQuit
        order = store.apps.sorted(by: .memory).map(\.id)
    }

    public var results: [AppUsage] {
        let apps = store.apps.filter { !$0.isProtected }.sorted(by: .memory).arranged(following: order)
        return Array(apps.matching(query).prefix(Self.limit))
    }

    /// The first row until the arrows choose another.
    public var highlighted: AppUsage? {
        let rows = results
        return rows.first { $0.id == selection } ?? rows.first
    }

    public func handle(_ key: QuickQuitKey) {
        switch key {
        case .previous: move(-1)
        case .next: move(1)
        case .quit: perform(force: false)
        case .forceQuit: perform(force: true)
        }
    }

    public func perform(force: Bool) {
        if let highlighted {
            onQuit(highlighted, force)
        }
    }

    func choose(_ app: AppUsage, force: Bool) {
        onQuit(app, force)
    }

    private func move(_ step: Int) {
        let rows = results
        guard let current = rows.firstIndex(where: { $0.id == highlighted?.id }) else { return }
        selection = rows[min(max(current + step, 0), rows.count - 1)].id
    }
}

/// ⌃⌥Q: find an app by name and quit it without touching the mouse.
public struct QuickQuitView: View {
    @Bindable private var state: QuickQuitState
    @FocusState private var isFocused: Bool

    public init(state: QuickQuitState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(loc("Type an app name"), text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
            let rows = state.results
            if rows.isEmpty {
                Text(loc("No matches"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            ForEach(rows) { row($0) }
            Text(loc("Return quits  ·  ⌥Return force quits  ·  Esc closes"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 520)
        .onAppear { isFocused = true }
    }

    private func row(_ app: AppUsage) -> some View {
        let isSelected = app.id == state.highlighted?.id
        return Button {
            state.choose(app, force: NSEvent.modifierFlags.contains(.option))
        } label: {
            HStack(spacing: 10) {
                AppGlyph(app: app, size: 22)
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(Format.size(Double(app.memory)))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(isSelected ? Palette.blue : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
