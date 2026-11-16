import GlassWorkCore
import SwiftUI

/// The side curves flow out into the screen edge, extending the notch's black surface.
struct IslandShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let corner = min(radius, rect.height / 2, rect.width / 2)
        let ear: CGFloat = min(10, rect.height / 3)
        return Path { path in
            path.move(to: CGPoint(x: -ear, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: ear), control: .zero)
            path.addLine(to: CGPoint(x: 0, y: rect.height - corner))
            path.addQuadCurve(
                to: CGPoint(x: corner, y: rect.height),
                control: CGPoint(x: 0, y: rect.height)
            )
            path.addLine(to: CGPoint(x: rect.width - corner, y: rect.height))
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: rect.height - corner),
                control: CGPoint(x: rect.width, y: rect.height)
            )
            path.addLine(to: CGPoint(x: rect.width, y: ear))
            path.addQuadCurve(
                to: CGPoint(x: rect.width + ear, y: 0),
                control: CGPoint(x: rect.width, y: 0)
            )
            path.closeSubpath()
        }
    }
}

struct IslandCapsule: View {
    let title: String
    var tint = Color(white: 0.12)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 29)
                .background(tint, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

struct IslandRow: View {
    let symbol: String
    let title: String
    var subtitle = ""
    var value = ""
    var tint = Color.white
    var valueTint: Color?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 2)
            if let action {
                Button(value, action: action).buttonStyle(.plain).foregroundStyle(tint)
            } else if !value.isEmpty {
                Text(value).foregroundStyle(valueTint ?? tint)
            }
        }
        .font(.system(size: 13))
        .monospacedDigit()
        .padding(.horizontal, 11)
        .frame(minHeight: 46)
        .padding(.vertical, 1)
        .background(Color(white: 0.075), in: .rect(cornerRadius: 13))
    }
}

struct IslandLevelBars: View {
    var tint = Palette.pink

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array([8.0, 16, 10, 14].enumerated()), id: \.offset) { _, height in
                Capsule().fill(tint).frame(width: 3, height: height)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
