import AppKit
import GlassWorkCore
import SwiftUI

/// A top-aligned surface. The host positions its center on the screen's notch.
public struct IslandView: View {
    private let store: IslandStore
    private let geometry: IslandGeometry
    private let actions: IslandActions
    /// Freezes time without changing production scheduling.
    var fixedNow: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    public init(store: IslandStore, geometry: IslandGeometry, actions: IslandActions = IslandActions()) {
        self.store = store
        self.geometry = geometry
        self.actions = actions
    }

    public var body: some View {
        Group {
            if let fixedNow {
                surface(now: fixedNow)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    surface(now: context.date)
                        .onChange(of: context.date) { _, date in store.tick(now: date) }
                }
            }
        }
        .id(reduceMotion ? String(describing: store.lifecycle.phase) : "island")
        .transition(.opacity)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onHover { inside in
            if inside {
                store.lifecycle.pointerEntered(at: Date())
            } else {
                store.lifecycle.pointerExited(at: Date())
            }
        }
        .onExitCommand { store.lifecycle.escape() }
        .task(id: store.lifecycle.nextDeadline) {
            guard fixedNow == nil, let deadline = store.lifecycle.nextDeadline else { return }
            do {
                try await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
                store.tick(now: Date())
            } catch {}
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.35), value: store.lifecycle.phase)
    }

    private func presentation(_ event: IslandEvent, now: Date) -> IslandPresentation {
        IslandPresentation(event: event, now: now, locale: locale, timeZone: timeZone)
    }

    @ViewBuilder
    private func surface(now: Date) -> some View {
        switch store.lifecycle.phase {
        case .idle, .peek:
            let peek = store.lifecycle.phase == .peek
            IslandShape(radius: 14).fill(.black)
                .frame(
                    width: peek ? geometry.peekFrame.width : geometry.notch.width,
                    height: peek ? geometry.peekFrame.height : geometry.notch.height
                )
                .contentShape(.rect)
                .onTapGesture { store.lifecycle.clicked() }
                .accessibilityLabel(loc("GlassWork Island"))
        case .compact:
            compact(now: now)
        case .expanded:
            expanded(now: now)
        }
    }

    private func compact(now: Date) -> some View {
        let wings = store.queue.wings
        let left = wings.left.map { presentation($0, now: now) }
        let right = wings.right.map { presentation($0, now: now) }
        let leftWidth = wingWidth(left?.compactLabel ?? "")
        let rightWidth: CGFloat = max(80, textWidth((right ?? left)?.compactValue ?? "") + (right == nil ? 30 : 52))
        return HStack(spacing: 0) {
            if let left {
                compactLeading(left).frame(width: leftWidth)
            }
            Color.clear.frame(width: geometry.notch.width)
            if let item = right ?? left {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if right != nil {
                        Image(systemName: item.symbol).foregroundStyle(item.tint)
                    }
                    Text(item.compactValue)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(item.tint).lineLimit(1)
                }
                .padding(.trailing, 15)
                .frame(width: rightWidth, height: geometry.notch.height)
                .overlay(alignment: .bottom) {
                    if wings.hasMore {
                        Circle().fill(.white.opacity(0.6)).frame(width: 4, height: 4).offset(y: -2)
                    }
                }
            }
        }
        .font(.system(size: 13))
        .frame(height: geometry.notch.height)
        .background(IslandShape(radius: 16).fill(.black))
        // Unequal wings still leave the transparent camera gap centered on the hardware.
        .offset(x: (rightWidth - leftWidth) / 2)
        .contentShape(.rect)
        .onTapGesture { store.lifecycle.clicked() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc("GlassWork Island, \(left?.title ?? "")"))
        .accessibilityValue([left?.compactValue, right?.title, right?.compactValue].compactMap(\.self)
            .joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.lifecycle.clicked() }
    }

    private func compactLeading(_ item: IslandPresentation) -> some View {
        HStack(spacing: 6) {
            if item.event.kind == .nowPlaying {
                IslandLevelBars(tint: item.tint)
            } else {
                Image(systemName: item.symbol).foregroundStyle(item.tint)
            }
            if !item.compactLabel.isEmpty {
                Text(item.compactLabel).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 15)
    }

    @ViewBuilder
    private func expanded(now: Date) -> some View {
        let pages = store.queue.pages
        if pages.indices.contains(store.page) {
            let event = pages[store.page]
            VStack(spacing: 4) {
                IslandExpandedCard(presentation: presentation(event, now: now), actions: actions)
                    .id(event.id)
                    .transition(.opacity)
                if pages.count > 1 {
                    pageDots(pages)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, geometry.notch.height + 12)
            .padding(.bottom, pages.count > 1 ? 6 : 16)
            .frame(width: max(380, geometry.notch.width + 32))
            .background(IslandShape(radius: 28).fill(.black))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(loc("GlassWork Island, \(presentation(event, now: now).title)"))
            .accessibilityAction(named: loc("Dismiss")) {
                store.dismiss(id: event.id)
                actions.dismiss(event.id)
            }
        } else {
            IslandShape(radius: 14).fill(.black)
                .frame(width: geometry.notch.width, height: geometry.notch.height)
        }
    }

    private func pageDots(_ pages: [IslandEvent]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, event in
                Button {
                    store.showPage(index)
                    actions.openPage(index)
                } label: {
                    Circle().fill(index == store.page ? .white : .white.opacity(0.35)).frame(width: 5, height: 5)
                        .padding(.vertical, 3)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(presentation(event, now: fixedNow ?? Date()).title)
                .accessibilityAddTraits(index == store.page ? .isSelected : [])
            }
        }
    }

    private func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
    }

    private func wingWidth(_ label: String) -> CGFloat {
        min(max(textWidth(label) + 52, 80), 220)
    }
}
