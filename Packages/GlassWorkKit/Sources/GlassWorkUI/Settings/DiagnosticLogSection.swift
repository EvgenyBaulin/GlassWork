import GlassWorkCore
import SwiftUI

/// The switch and, once it is on, where the log is and what can be done with it.
public struct DiagnosticLogSection: View {
    @Binding private var isOn: Bool
    private let path: String
    private let size: Int
    private let reveal: () -> Void
    private let send: () -> Void

    public init(
        isOn: Binding<Bool>,
        path: String,
        size: Int,
        reveal: @escaping () -> Void,
        send: @escaping () -> Void
    ) {
        _isOn = isOn
        self.path = path
        self.size = size
        self.reveal = reveal
        self.send = send
    }

    public var body: some View {
        Section(loc("Diagnostics")) {
            Toggle(isOn: $isOn) {
                Text(loc("Keep diagnostic log"))
                Text(loc("Off by default. Local file only; nothing is sent unless you click Send."))
            }
            if isOn {
                Text(verbatim: details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Button(loc("Reveal log"), action: reveal)
                    Button(loc("Send to developer…"), action: send)
                    Spacer()
                }
                Text(loc("Turning this off deletes the log."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var details: String {
        "\(path) · \(Format.size(Double(size))) · \(loc("keeps \(DiagnosticLog.keepDays) days"))"
    }
}
