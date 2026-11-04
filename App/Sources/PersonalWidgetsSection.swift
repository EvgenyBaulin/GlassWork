import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Where the user turns on the widgets that show their own photos and contacts.
///
/// These buttons are the only way to the macOS prompts: nothing else in the app asks for this access.
struct PersonalWidgetsSection: View {
    let store: SettingsStore
    let personal: PersonalWidgetStore

    private var settings: PersonalWidgetSettings {
        store.settings.personalWidgets
    }

    var body: some View {
        Section {
            photoFrame
            onThisDay
            birthdays
            Text(loc("These stay off until you turn them on. Photos and names stay on this Mac."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(loc("Photos and birthdays"))
        }
    }

    private var photoFrame: some View {
        LabeledContent {
            HStack {
                Button(settings.isPhotoFrameOn ? loc("Change Folder…") : loc("Choose Folder…")) { chooseFolder() }
                if settings.isPhotoFrameOn {
                    Button(loc("Turn Off")) { update { $0.isPhotoFrameOn = false } }
                }
            }
        } label: {
            Text(WidgetKind.photoFrame.title)
            if settings.isPhotoFrameOn {
                Text(settings.photoFolderPath).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var onThisDay: some View {
        row(
            kind: .onThisDay,
            isOn: settings.isOnThisDayOn,
            access: personal.photosAccess,
            turnOn: {
                let access = await personal.requestPhotos()
                update { $0.isOnThisDayOn = access == .granted }
            },
            turnOff: { update { $0.isOnThisDayOn = false } }
        )
    }

    private var birthdays: some View {
        row(
            kind: .birthdays,
            isOn: settings.isBirthdaysOn,
            access: personal.contactsAccess,
            turnOn: {
                let access = await personal.requestContacts()
                update { $0.isBirthdaysOn = access == .granted }
            },
            turnOff: { update { $0.isBirthdaysOn = false } }
        )
    }

    private func row(
        kind: WidgetKind,
        isOn: Bool,
        access: PersonalAccess,
        turnOn: @escaping @MainActor () async -> Void,
        turnOff: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            if isOn {
                Button(loc("Turn Off"), action: turnOff)
            } else {
                Button(loc("Turn On")) { Task { await turnOn() } }
            }
        } label: {
            Text(kind.title)
            if access == .denied {
                Text(loc("Allow GlassWork in System Settings › Privacy & Security."))
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = loc("Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        update {
            $0.photoFolderPath = url.path(percentEncoded: false)
            $0.isPhotoFrameOn = true
        }
    }

    /// Reads or clears right away, so the widget does not wait for its next refresh.
    private func update(_ change: (inout PersonalWidgetSettings) -> Void) {
        store.update { change(&$0.personalWidgets) }
        let settings = store.settings.personalWidgets
        Task { await personal.refresh(settings, for: WidgetKind.personalKinds, force: true) }
    }
}
