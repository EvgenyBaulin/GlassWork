@testable import GlassWorkCore
import Testing

struct CalendarOptionsTests {
    private let work = CalendarChoice(id: "work", title: "Work", account: "iCloud", color: "#3B82F6")
    private let birthdays = CalendarChoice(
        id: "birthdays", title: "Birthdays", account: "Other", color: "#8E8E93", isBirthdays: true
    )

    @Test func birthdaysStartHidden() {
        let options = CalendarOptions()
        #expect(options.shows(work))
        #expect(options.shows(birthdays) == false)
    }

    @Test func aStoredListDecidesEverything() {
        let options = CalendarOptions(options: [ItemOption.hiddenCalendars: "work"])
        #expect(options.shows(work) == false)
        #expect(options.shows(birthdays))
    }

    @Test func theFirstChoiceKeepsBirthdaysHidden() {
        let value = CalendarOptions().stored(after: work, isShown: false, among: [work, birthdays])
        #expect(value == "birthdays,work")
    }

    @Test func showingTheLastHiddenCalendarLeavesAnEmptyList() {
        let value = CalendarOptions().stored(after: birthdays, isShown: true, among: [work, birthdays])
        #expect(value.isEmpty)
        let options = CalendarOptions(options: [ItemOption.hiddenCalendars: value])
        #expect(options.shows(birthdays))
        #expect(options.shows(work))
    }
}
