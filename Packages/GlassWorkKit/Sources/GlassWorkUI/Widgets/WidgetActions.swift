import GlassWorkCore
import SwiftUI

/// Turns a label into a working button.
///
/// The shared views cannot name an App Intent: intents must live in the extension to be found. So each host
/// supplies its own button: the extension one that runs an intent, the app one that calls the model directly.
public struct WidgetActionRenderer: Sendable {
    let render: @MainActor @Sendable (WidgetCommand.Action, AnyView) -> AnyView

    public init(_ render: @escaping @MainActor @Sendable (WidgetCommand.Action, AnyView) -> AnyView) {
        self.render = render
    }

    /// Shows the label and does nothing, for previews and tests.
    public static let inert = WidgetActionRenderer { _, label in label }
}

public extension EnvironmentValues {
    @Entry var widgetActions = WidgetActionRenderer.inert
}

/// A control inside a widget. When disabled it is only a picture, so a click cannot reach the app.
struct WidgetActionButton<Label: View>: View {
    let action: WidgetCommand.Action
    var isEnabled = true
    @ViewBuilder let label: () -> Label
    @Environment(\.widgetActions) private var actions

    var body: some View {
        if isEnabled {
            actions.render(action, AnyView(label()))
        } else {
            label().opacity(0.45)
        }
    }
}
