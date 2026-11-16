import GlassWorkCore
import SwiftUI

/// Shared by the panel, widget columns and the Dock's widget face.
enum AISpendText {
    static func usesRequests(_ spend: AISpend) -> Bool {
        spend.today.aiCredits == 0 && spend.last7Days.aiCredits == 0 && spend.month.aiCredits == 0
            && max(spend.today.premiumRequests, spend.last7Days.premiumRequests, spend.month.premiumRequests) > 0
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    static func today(_ spend: AISpend) -> String {
        number(usesRequests(spend) ? spend.today.premiumRequests : spend.today.aiCredits)
    }

    static func summary(_ spend: AISpend) -> String {
        if usesRequests(spend) {
            return loc("\(today(spend)) requests today · \(number(spend.month.premiumRequests)) this month")
        }
        return loc("\(today(spend)) AI credits today · \(number(spend.month.aiCredits)) this month")
    }

    static func unit(_ spend: AISpend) -> String {
        usesRequests(spend) ? loc("requests today") : loc("AI credits today")
    }
}

struct AISpendView: View {
    let spend: AISpend
    var fontSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AISpendText.summary(spend))
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(loc("This Mac's sessions"))
                .font(.system(size: fontSize - 1))
                .foregroundStyle(.tertiary)
        }
    }
}
