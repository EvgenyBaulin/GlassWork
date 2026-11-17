import GlassWorkCore
import SwiftUI

public extension OnboardingSet {
    var title: String {
        switch self {
        case .developer: loc("Developer")
        case .day: loc("Day")
        case .mac: loc("Mac")
        }
    }

    var summary: String {
        switch self {
        case .developer: loc("Git, dev servers, Docker, Ping, VPN, Wi-Fi and AI usage")
        case .day: loc("Calendar, timers, world clocks, Now Playing and Ends In")
        case .mac: loc("Overview, CPU, memory, disk, network, battery, sensors and fans")
        }
    }

    var symbol: String {
        switch self {
        case .developer: "hammer"
        case .day: "sun.max"
        case .mac: "desktopcomputer"
        }
    }
}

/// Cards for the three sets; a tap adds or removes one.
public struct OnboardingSetPicker: View {
    @Binding private var selected: Set<OnboardingSet>

    public init(selected: Binding<Set<OnboardingSet>>) {
        _selected = selected
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(OnboardingSet.allCases) { set in
                let isOn = selected.contains(set)
                Button {
                    if isOn {
                        selected.remove(set)
                    } else {
                        selected.insert(set)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: set.symbol).font(.title3).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.title).font(.headline)
                            Text(set.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? Color.accentColor : .secondary)
                    }
                    .padding(10)
                    .background(isOn ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(isOn ? Color.accentColor : .secondary.opacity(0.3)))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// The permissions the chosen sets ask for, with the same rows as the Permissions page.
public struct OnboardingPermissionsView: View {
    private let rows: [PermissionRowModel]
    private let open: (Permission) -> Void

    public init(rows: [PermissionRowModel], open: @escaping (Permission) -> Void) {
        self.rows = rows
        self.open = open
    }

    public var body: some View {
        if rows.isEmpty {
            Text(loc("Nothing is needed for what you chose. Each module asks for access only when you turn it on."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    PermissionRow(row) { open(row.permission) }
                }
            }
        }
    }
}

/// The last step: what was switched on, and where to go next.
public struct OnboardingSummaryView: View {
    @Binding private var launchAtLogin: Bool
    private let sets: [OnboardingSet]
    private let openSettings: () -> Void
    private let addWidgets: () -> Void

    public init(
        sets: [OnboardingSet],
        launchAtLogin: Binding<Bool>,
        openSettings: @escaping () -> Void,
        addWidgets: @escaping () -> Void
    ) {
        self.sets = sets
        _launchAtLogin = launchAtLogin
        self.openSettings = openSettings
        self.addWidgets = addWidgets
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text(loc("All set")).font(.title.weight(.semibold))
            Text(sets.isEmpty
                ? loc("Overview, CPU and Memory are in the menu bar. Everything else waits in the Hub.")
                :
                loc(
                    "Switched on: \(sets.map(\.title).joined(separator: ", ")). They wait in the Hub, and the main ones are in the menu bar."
                ))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Toggle(loc("Launch at login"), isOn: $launchAtLogin).toggleStyle(.checkbox)
            HStack {
                Button(loc("Open Settings"), action: openSettings)
                Button(loc("Add widgets"), action: addWidgets)
            }
        }
    }
}
