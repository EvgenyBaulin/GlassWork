import GlassWorkCore
import SwiftUI

/// Language, clock and first day of the week.
public struct RegionalSection: View {
    @Binding private var settings: RegionalSettings
    /// What the language is now. It only changes after a restart, so the note shows while it differs.
    private let runningLanguage: AppLanguage

    public init(settings: Binding<RegionalSettings>, runningLanguage: AppLanguage) {
        _settings = settings
        self.runningLanguage = runningLanguage
    }

    public var body: some View {
        Section(loc("Language and time")) {
            Picker(loc("Language"), selection: $settings.language) {
                Text(loc("System")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.english)
                Text("Русский").tag(AppLanguage.russian)
            }
            if settings.language != runningLanguage {
                Text(loc("Restart GlassWork to apply the language."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(loc("Time format"), selection: $settings.timeFormat) {
                Text(loc("System")).tag(TimeFormat.system)
                Text(loc("12-hour")).tag(TimeFormat.twelveHour)
                Text(loc("24-hour")).tag(TimeFormat.twentyFourHour)
            }
            Picker(loc("First day of the week"), selection: $settings.firstWeekday) {
                Text(loc("System")).tag(FirstWeekday.system)
                Text(loc("Monday")).tag(FirstWeekday.monday)
                Text(loc("Sunday")).tag(FirstWeekday.sunday)
            }
        }
    }
}

/// The background rebuild: whether it is on, when it last built and when it checks next. Read-only.
public struct AutoUpdateSection: View {
    private let status: AutoUpdateStatus
    private let hasLog: Bool
    private let viewLog: () -> Void

    public init(status: AutoUpdateStatus, hasLog: Bool, viewLog: @escaping () -> Void) {
        self.status = status
        self.hasLog = hasLog
        self.viewLog = viewLog
    }

    public var body: some View {
        Section(loc("Updates")) {
            LabeledContent(loc("Background update")) {
                Text(status.isInstalled ? loc("On") : loc("Off"))
                    .foregroundStyle(status.isInstalled ? .green : .secondary)
            }
            LabeledContent(loc("Last build"), value: status.lastBuild.map(Self.text) ?? loc("Never"))
            if status.isInstalled {
                LabeledContent(loc("Next check"), value: Self.text(status.nextCheck))
                if let next = status.nextBuild {
                    LabeledContent(loc("Next rebuild"), value: Self.text(next))
                }
            } else {
                Text(loc("Turn it on in Terminal: make auto-update-on"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(loc("View log"), action: viewLog).disabled(!hasLog)
                Spacer()
            }
        }
    }

    private static func text(_ date: Date) -> String {
        date.dateTimeText
    }
}
