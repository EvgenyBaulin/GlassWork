import AppIntents
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Runs one widget button. The extension can only pass the request on: it writes the command to the shared
/// container and wakes the app, which checks it against the current state and does the work.
struct WidgetActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Widget Action"
    /// Only widget buttons may run this, so it stays out of Shortcuts and Spotlight.
    static let isDiscoverable = false

    @Parameter(title: "Action")
    var action: String

    init() {}

    init(action: WidgetCommand.Action) {
        self.action = action.encoded
    }

    func perform() async throws -> some IntentResult {
        guard let action = WidgetCommand.Action(encoded: action), isAllowed(action) else { return .result() }
        try WidgetCommandInbox().send(WidgetCommand(action: action))
        WidgetCommandSignal.post()
        return .result()
    }

    /// Fans stay as they are unless the app last said control is on. The app checks again on its side.
    private func isAllowed(_ action: WidgetCommand.Action) -> Bool {
        guard action.isFanAction else { return true }
        return SnapshotStore().read(WidgetSnapshot.self, for: WidgetSnapshot.key)?.fans?.canControl == true
    }
}

extension WidgetActionRenderer {
    static let intents = WidgetActionRenderer { action, label in
        AnyView(Button(intent: WidgetActionIntent(action: action)) { label }.buttonStyle(.plain))
    }
}
