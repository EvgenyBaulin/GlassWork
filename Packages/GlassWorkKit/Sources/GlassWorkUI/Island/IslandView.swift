import AppKit
import GlassWorkCore
import SwiftUI

/// A top-aligned surface. The host positions its center on the screen's notch.
public struct IslandView: View {
    private let store: IslandStore
    private let geometry: IslandGeometry
    private let actions: IslandActions
    private let tracksHover: Bool
    private let appMenuMaxX: CGFloat?
    private let statusItemsMinX: CGFloat?
    /// Freezes time without changing production scheduling.
    var fixedNow: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    public init(
        store: IslandStore, geometry: IslandGeometry, actions: IslandActions = IslandActions(),
        appMenuMaxX: CGFloat? = nil, statusItemsMinX: CGFloat? = nil, tracksHover: Bool = true
    ) {
        self.store = store
        self.geometry = geometry
        self.actions = actions
        self.tracksHover = tracksHover
        self.appMenuMaxX = appMenuMaxX
        self.statusItemsMinX = statusItemsMinX
    }

    public var body: some View {
        Group {
            if let fixedNow {
                surface(now: fixedNow)
            } else if store.lifecycle.phase == .compact || store.lifecycle.phase == .expanded {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    surface(now: context.date)
                        .onChange(of: context.date) { _, date in store.tick(now: date) }
                }
            } else {
                surface(now: Date())
            }
        }
        .id(reduceMotion ? String(describing: store.lifecycle.phase) : "island")
        .transition(.opacity)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onHover { inside in
            guard tracksHover else { return }
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
        if let preview = store.dropPreview {
            dropZone(preview)
        } else {
            phaseSurface(now: now)
        }
    }

    private func dropZone(_ preview: IslandDropPreview) -> some View {
        IslandShelfDropZone(preview: preview)
            .padding(.horizontal, 16)
            .padding(.top, geometry.notch.height + 12)
            .padding(.bottom, 16)
            .frame(width: expandedWidth)
            .background(IslandShape(radius: 28).fill(.black))
            .accessibilityLabel(loc("GlassWork Island, \(loc("Drop to park on the Shelf"))"))
    }

    @ViewBuilder
    private func phaseSurface(now: Date) -> some View {
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
        let layout = compactWings(now: now)
        let leftWidth = layout.left
        let rightWidth = layout.right
        return HStack(spacing: 0) {
            if let left {
                compactLeading(left, iconOnly: layout.isLeftIconOnly).frame(width: leftWidth).clipped()
            }
            Color.clear.frame(width: geometry.notch.width)
            if let item = right ?? left {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if right != nil {
                        Image(systemName: item.symbol).foregroundStyle(item.tint)
                    }
                    if layout.movesLabelRight, let left, !left.compactLabel.isEmpty {
                        Text(left.compactLabel).lineLimit(1)
                    }
                    Text(item.compactValue)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(item.tint).lineLimit(1)
                }
                .padding(.trailing, 15)
                .frame(width: rightWidth, height: geometry.notch.height)
                .clipped()
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

    private func compactLeading(_ item: IslandPresentation, iconOnly: Bool) -> some View {
        HStack(spacing: 6) {
            if item.event.kind == .nowPlaying {
                IslandLevelBars(tint: item.tint)
            } else {
                Image(systemName: item.symbol).foregroundStyle(item.tint)
            }
            if !iconOnly, !item.compactLabel.isEmpty {
                Text(item.compactLabel).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 15)
    }

    @ViewBuilder
    private func expanded(now: Date) -> some View {
        let pages = store.queue.pages
        if showsMiniWidgets {
            miniWidgetsSurface(now: now)
        } else if pages.indices.contains(store.page) {
            let event = pages[store.page]
            VStack(spacing: 4) {
                ScrollView {
                    IslandExpandedCard(presentation: presentation(event, now: now), actions: actions)
                        .id(event.id)
                        .transition(.opacity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: cardHeight(now: now))
                if pages.count > 1 {
                    pageDots(pages)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, geometry.notch.height + 12)
            .padding(.bottom, pages.count > 1 ? 6 : 16)
            .frame(width: expandedWidth)
            .background(IslandShape(radius: 28).fill(.black))
            .onTapGesture { store.lifecycle.clicked() }
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

    private func miniWidgetsSurface(now: Date) -> some View {
        VStack(spacing: 4) {
            ScrollView {
                IslandMiniWidgetsCard(store: store, actions: actions)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: cardHeight(now: now))
        }
        .padding(.horizontal, 16)
        .padding(.top, geometry.notch.height + 12)
        .padding(.bottom, 16)
        .frame(width: expandedWidth)
        .background(IslandShape(radius: 28).fill(.black))
        .onTapGesture {
            if !store.isEditingWidgets {
                store.lifecycle.clicked()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(loc("GlassWork Island, \(loc("Opened by you · your widgets"))"))
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

    /// Screen-space bounds shared with the panel host. Compact wings retain the camera's center.
    public func surfaceFrame(now: Date) -> CGRect {
        if store.dropPreview != nil {
            return geometry.expandedFrame(size: CGSize(
                width: expandedWidth, height: geometry.notch.height + 12 + IslandShelfDropZone.height + 16
            ))
        }
        return switch store.lifecycle.phase {
        case .idle: geometry.notch
        case .peek: geometry.peekFrame
        case .compact:
            geometry.compactFrame(leftWing: compactWings(now: now).left, rightWing: compactWings(now: now).right)
        case .expanded:
            store.queue.events.isEmpty && !showsMiniWidgets ? geometry.notch : geometry.expandedFrame(size: CGSize(
                width: expandedWidth,
                height: geometry.notch.height + 12 + cardHeight(now: now) + footerHeight
            ))
        }
    }

    /// Uses the same curved outline as the visible surface, including its ears at the screen edge.
    public func contains(_ point: CGPoint, in frame: CGRect) -> Bool {
        let radius: CGFloat = switch store.lifecycle.phase {
        case _ where store.dropPreview != nil: 28
        case .idle, .peek: 14
        case .compact: 16
        case .expanded: store.queue.events.isEmpty && !showsMiniWidgets ? 14 : 28
        }
        return IslandShape(radius: radius).path(in: CGRect(origin: .zero, size: frame.size))
            .contains(CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y))
    }

    private var expandedWidth: CGFloat {
        min(480, max(380, geometry.notch.width + 32))
    }

    private var footerHeight: CGFloat {
        store.queue.pages.count > 1 ? 21 : 16
    }

    /// Opened by the user with no event to show: the mini widgets fill the card.
    private var showsMiniWidgets: Bool {
        store.lifecycle.opensWidgets && store.queue.events.isEmpty
    }

    private func cardHeight(now: Date) -> CGFloat {
        if showsMiniWidgets {
            let card = IslandMiniWidgetsCard(store: store, actions: actions)
                .frame(width: expandedWidth - 32)
                .environment(\.locale, locale)
                .environment(\.timeZone, timeZone)
            return NSHostingView(rootView: card).fittingSize.height
        }
        let pages = store.queue.pages
        guard pages.indices.contains(store.page) else { return 0 }
        let card = IslandExpandedCard(presentation: presentation(pages[store.page], now: now), actions: actions)
            .frame(width: expandedWidth - 32)
            .environment(\.locale, locale)
            .environment(\.timeZone, timeZone)
        let height = NSHostingView(rootView: card).fittingSize.height
        return min(height, max(0, 420 - geometry.notch.height - 12 - footerHeight))
    }

    private func compactWings(now: Date) -> IslandWings {
        let occupants = store.queue.wings
        let left = occupants.left.map { presentation($0, now: now) }
        let right = occupants.right.map { presentation($0, now: now) }
        let wantedLeft = wingWidth(left?.compactLabel ?? "")
        let menuMaxX = appMenuMaxX ?? geometry.notch.minX - wantedLeft
        let movesLabel = geometry.notch.minX - menuMaxX < wantedLeft
        let wantedRight = max(80, textWidth((right ?? left)?.compactValue ?? "") + (right == nil ? 30 : 52))
            + (movesLabel ? textWidth(left?.compactLabel ?? "") + 6 : 0)
        return IslandGeometry.wings(
            appMenuMaxX: menuMaxX, statusItemsMinX: statusItemsMinX ?? geometry.notch.maxX + wantedRight,
            notch: geometry.notch, wanted: wantedLeft, wanted: wantedRight, iconOnly: 44
        )
    }

    private func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
    }

    private func wingWidth(_ label: String) -> CGFloat {
        min(max(textWidth(label) + 52, 80), 220)
    }
}
