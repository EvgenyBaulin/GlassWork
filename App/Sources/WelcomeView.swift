import AppKit
import GlassWorkCore
import GlassWorkUI
import ServiceManagement
import SwiftUI

/// Four steps with Skip: welcome, what to enable, permissions for it, done.
struct WelcomeView: View {
    let store: SettingsStore
    let openSettings: () -> Void
    let addWidgets: () -> Void
    let finish: () -> Void
    @State private var step = 0
    @State private var launchAtLogin = true
    @State private var sets: Set<OnboardingSet> = []
    @State private var granted: Set<Permission> = []

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            content
            Spacer()
            HStack {
                Button(loc("Skip")) { complete() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(step == 3 ? loc("Done") : loc("Continue")) { advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            Text(loc("Welcome to GlassWork")).font(.largeTitle.weight(.semibold))
            Text(loc("Live figures in your menu bar, with everything else one click away in the Hub."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case 1:
            Text(loc("What to enable")).font(.title.weight(.semibold))
            Text(loc("Overview, CPU and Memory start in the menu bar. Pick sets to add more."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            OnboardingSetPicker(selected: $sets)
        case 2:
            Text(loc("Permissions")).font(.title.weight(.semibold))
            OnboardingPermissionsView(rows: permissionRows, open: PermissionReader.openSettings)
                .task { await refreshGranted() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await refreshGranted() }
                }
        default:
            OnboardingSummaryView(
                sets: OnboardingSet.allCases.filter(sets.contains),
                launchAtLogin: $launchAtLogin,
                openSettings: { complete(then: openSettings) },
                addWidgets: { complete(then: addWidgets) }
            )
        }
    }

    /// Only what the chosen sets need, including the permissions already given.
    private var permissionRows: [PermissionRowModel] {
        let needed = OnboardingSet.permissions(of: sets, in: store.settings)
        return Permission.allCases.filter(needed.contains).map { permission in
            PermissionRowModel(
                permission: permission,
                state: PermissionNeeds.state(isNeeded: true, isGranted: granted.contains(permission))
            )
        }
    }

    private func refreshGranted() async {
        granted = await PermissionReader.granted()
    }

    private func advance() {
        switch step {
        case 1:
            // One change, so a single undo takes the whole choice back.
            let chosen = sets
            store.update { OnboardingSet.apply(chosen, to: &$0) }
            step += 1
        case 3:
            complete()
        default:
            step += 1
        }
    }

    private func complete(then next: (() -> Void)? = nil) {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        }
        store.update { $0.welcomeCompleted = true }
        finish()
        next?()
    }
}
