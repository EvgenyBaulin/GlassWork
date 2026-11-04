import GlassWorkCore
import SwiftUI
import WidgetKit

/// Who has a birthday next, from Contacts.
struct BirthdaysWidget: View {
    let context: TimeContext

    private let symbol = "gift.fill"

    private static let tints = [Palette.pink, Palette.blue, Palette.purple, Palette.orange, Palette.green, Palette.teal]

    private var data: BirthdaysData? {
        context.snapshot.personal?.birthdays
    }

    /// A birthday that has passed since the last read drops off without waiting for the app.
    private var people: [WidgetBirthday] {
        let today = Calendar.current.startOfDay(for: context.now)
        return (data?.people ?? []).filter { $0.date >= today }
    }

    var body: some View {
        if let data {
            switch data.state {
            case .off, .noAccess, .unreadable:
                WidgetTurnOnCard(
                    symbol: symbol,
                    tint: Palette.pink,
                    title: data.state == .off ? loc("Birthdays from Contacts") : loc("No access to Contacts"),
                    detail: loc("GlassWork reads only names and birthdays. Nothing leaves this Mac."),
                    action: loc("Turn On"),
                    compact: context.size == .small
                )
            case .ready where people.isEmpty:
                WidgetEmptyState(
                    symbol: symbol,
                    title: loc("No birthdays in Contacts"),
                    detail: context.size == .small ? nil : loc("Add birthdays to your contacts to see them here."),
                    tint: Palette.pink
                )
            case .ready:
                content(data)
            }
        } else {
            WidgetChecking(symbol: symbol, tint: Palette.pink)
        }
    }

    @ViewBuilder
    private func content(_ data: BirthdaysData) -> some View {
        switch context.size {
        case .small:
            lead
        case .medium:
            HStack(spacing: 14) {
                lead.frame(width: 140)
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    WidgetSection(title: loc("Next"))
                    ForEach(Array(people.dropFirst().prefix(3).enumerated()), id: \.element.id) { index, person in
                        HStack(spacing: 7) {
                            avatar(person, index: index + 1, size: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(person.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(verbatim: "\(wait(person)) · \(day(person))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    WidgetHeader(title: loc("Birthdays"), symbol: symbol, tint: Palette.pink)
                    Spacer(minLength: 6)
                    Text(loc("People: \(data.total)")).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                ForEach(Array(people.prefix(6).enumerated()), id: \.element.id) { index, person in
                    row(person, index: index)
                }
                Spacer(minLength: 0)
            }
        case .extraLarge:
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: loc("Birthdays"), symbol: symbol, tint: Palette.pink)
                HStack(alignment: .top, spacing: 18) {
                    column(Array(people.prefix(4)), start: 0)
                    Divider()
                    column(Array(people.dropFirst(4).prefix(4)), start: 4)
                }
                Spacer(minLength: 0)
                Text(loc("From Contacts · People: \(data.total)"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func column(_ list: [WidgetBirthday], start: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let first = list.first {
                WidgetSection(title: first.date.formatted(.dateTime.month(.wide)))
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, person in
                row(person, index: start + index)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var lead: some View {
        if let person = people.first {
            VStack(alignment: .leading, spacing: 3) {
                WidgetHeader(title: loc("Birthdays"), symbol: symbol, tint: Palette.pink)
                avatar(person, index: 0, size: 44).padding(.vertical, 2)
                Text(person.name.split(separator: " ").first.map(String.init) ?? person.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(wait(person))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.pink)
                    .lineLimit(1)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(detail(person)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ person: WidgetBirthday, index: Int) -> some View {
        let days = BirthdayPlanner.daysUntil(person, from: context.now)
        return HStack(spacing: 9) {
            avatar(person, index: index, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(person.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail(person)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(countdown(person))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(days <= 7 ? Palette.pink : .primary)
                .lineLimit(1)
        }
    }

    private func avatar(_ person: WidgetBirthday, index: Int, size: CGFloat) -> some View {
        Text(verbatim: person.initials)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .widgetSolid(Self.tints[index % Self.tints.count], in: .circle)
    }

    private func day(_ person: WidgetBirthday) -> String {
        person.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func detail(_ person: WidgetBirthday) -> String {
        guard let turns = person.turns else { return day(person) }
        return "\(day(person)) · \(loc("turns \(turns)"))"
    }

    /// "in 3 days", as a sentence.
    private func wait(_ person: WidgetBirthday) -> String {
        let days = BirthdayPlanner.daysUntil(person, from: context.now)
        return days == 0 ? loc("Today") : loc("in \(days) days to a birthday")
    }

    /// "3 days", for a column of numbers.
    private func countdown(_ person: WidgetBirthday) -> String {
        let days = BirthdayPlanner.daysUntil(person, from: context.now)
        return days == 0 ? loc("Today") : loc("\(days) days away")
    }
}
