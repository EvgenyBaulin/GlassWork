import GlassWorkCore
import SwiftUI
import WidgetKit

extension Font {
    /// The large number a widget leads with.
    static func widgetFigure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

/// Header of the large sizes: a colored tile, the title and a note on the right.
struct WidgetTitle: View {
    let title: String
    let symbol: String
    let tint: Color
    var note = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .widgetSolid(tint, in: .rect(cornerRadius: 7))
            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 8)
            Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// White text on a solid color, or plain text on a soft fill once the system recolors the widget:
/// in tinted and clear modes a text and its fill turn the same color, and the text disappears.
private struct WidgetSolid<Fill: Shape>: ViewModifier {
    let tint: Color?
    let shape: Fill
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        if let tint, renderingMode == .fullColor {
            content.foregroundStyle(.white).background(tint.gradient, in: shape)
        } else {
            content.foregroundStyle(.primary).background(.quaternary, in: shape)
        }
    }
}

extension View {
    /// `tint` nil gives the soft fill in every mode.
    func widgetSolid(_ tint: Color?, in shape: some Shape) -> some View {
        modifier(WidgetSolid(tint: tint, shape: shape))
    }
}

/// Small capitals above a group of rows.
struct WidgetSection: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// What a widget shows when it has nothing to show yet.
struct WidgetEmptyState: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = Palette.gray

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown until the app has sent this widget's data. "None found" would be a false statement at that point.
struct WidgetChecking: View {
    let symbol: String
    let tint: Color

    var body: some View {
        WidgetEmptyState(symbol: symbol, title: loc("Checking…"), tint: tint)
    }
}

/// Orange note that the data below is not fresh.
struct WidgetStaleBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "wifi.slash")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.orange)
            .lineLimit(1)
            .widgetAccentable()
    }
}

/// Label on the left, value on the right, sized for the large widgets.
struct WidgetFact: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).fontWeight(.medium).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 12))
    }
}

/// `▲ 15% vs average`: more than usual is orange, less is green.
struct WidgetChange: View {
    let change: Double
    let text: String

    var body: some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
        }
        .labelStyle(WidgetTightLabel())
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(change >= 0 ? Palette.orange : Palette.green)
        .widgetAccentable()
    }
}

struct WidgetTightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// Rounded square with the app's first letter, standing in for its icon: the extension cannot read other apps.
struct WidgetAppBadge: View {
    let app: String
    var size: CGFloat = 18

    private static let tints = [Palette.blue, Palette.teal, Palette.purple, Palette.pink, Palette.red, Palette.orange]

    private var tint: Color {
        let sum = app.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.tints[sum % Self.tints.count]
    }

    var body: some View {
        Text(verbatim: String(app.prefix(1)).uppercased())
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .widgetSolid(tint, in: .rect(cornerRadius: size / 4))
    }
}

/// App name, a share bar and the time, as Most Used and Screen Time list them.
struct WidgetAppRow: View {
    let app: String
    let seconds: Double
    let peak: Double
    let tint: Color
    var barWidth: CGFloat = 90

    var body: some View {
        HStack(spacing: 8) {
            WidgetAppBadge(app: app)
            Text(app).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer(minLength: 6)
            ThinBar(value: seconds / max(peak, 1), tint: tint).frame(width: barWidth)
            Text(WidgetDuration.short(seconds))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}

/// Times on the Screen Time widgets: `5h 12m` and `43m`.
enum WidgetDuration {
    static func short(_ seconds: Double) -> String {
        CompactDuration.format(seconds)
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func range(_ start: Date, _ end: Date) -> String {
        "\(clock(start)) – \(clock(end))"
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// Short labels under a bar chart, spread evenly.
struct WidgetAxisLabels: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
