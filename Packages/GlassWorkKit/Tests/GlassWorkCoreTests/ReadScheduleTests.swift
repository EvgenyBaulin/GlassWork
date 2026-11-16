import Foundation
@testable import GlassWorkCore
import Testing

@MainActor
struct ReadScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_794_850_000)

    private func wait(_ plan: ReadPlan, tick: TimeInterval = 2) -> TimeInterval {
        ReadSchedule.nextWake(now: now, tickInterval: tick, plan: plan).timeIntervalSince(now)
    }

    @Test func aPacedMetricIsDueHalfASecondBeforeItsPace() {
        let last = now.addingTimeInterval(-3)
        #expect(ReadSchedule.dueDate(last: last, pace: 10, now: now) == last.addingTimeInterval(9.5))
        #expect(ReadSchedule.dueDate(last: nil, pace: 10, now: now) == now)
        #expect(ReadSchedule.dueDate(last: last, pace: nil, now: now) == now)
        // A clock that moved back makes it due at once, as `SampleKind.isDue` does.
        #expect(ReadSchedule.dueDate(last: now.addingTimeInterval(60), pace: 10, now: now) == now)
    }

    @Test func theLoopSleepsUntilTheEarliestDueDate() {
        let plan = ReadPlan(dates: [now.addingTimeInterval(9), now.addingTimeInterval(5), now.addingTimeInterval(20)])

        let seconds = wait(plan)

        #expect(abs(seconds - 5.05) < 0.001)
    }

    @Test func aReadOnEveryTickKeepsTheTickInterval() {
        let plan = ReadPlan(everyTick: true, dates: [now.addingTimeInterval(20)])

        #expect(wait(plan, tick: 2) == 2)
        #expect(wait(plan, tick: 8) == 8)
    }

    @Test func theSleepIsBetweenOneAndThirtySeconds() {
        #expect(wait(ReadPlan()) == 30)
        #expect(wait(ReadPlan(dates: [now.addingTimeInterval(300)])) == 30)
        #expect(wait(ReadPlan(dates: [now])) == 1)
        #expect(wait(ReadPlan(dates: [now.addingTimeInterval(-40)])) == 1)
    }

    @Test func aTickShorterThanASecondIsNotStretched() {
        #expect(wait(ReadPlan(everyTick: true), tick: 0.5) == 0.5)
    }

    @Test func batteryAndVolumesFollowEventsWithASlowBackstop() {
        let last = now.addingTimeInterval(-10)

        #expect(!ReadSchedule.isDue(last: last, interval: 60, event: false, at: now))
        #expect(ReadSchedule.isDue(last: last, interval: 60, event: true, at: now))
        #expect(ReadSchedule.isDue(last: nil, interval: 60, event: false, at: now))
        #expect(ReadSchedule.isDue(last: now.addingTimeInterval(-59.6), interval: 60, event: false, at: now))
    }

    @Test func anEventMakesTheReadDueAtOnce() {
        let last = now.addingTimeInterval(-10)

        let quiet = ReadSchedule.eventDrivenDate(last: last, interval: 60, event: false, now: now)
        let plugged = ReadSchedule.eventDrivenDate(last: last, interval: 60, event: true, now: now)

        #expect(quiet == last.addingTimeInterval(59.5))
        #expect(plugged == now)
        #expect(wait(ReadPlan(dates: [plugged])) == 1)
    }

    @Test func anOpenPanelKeepsTheOldPace() {
        #expect(ReadSchedule.eventDrivenInterval(panelOpen: true, panelInterval: 30) == 30)
        #expect(ReadSchedule.eventDrivenInterval(panelOpen: false, panelInterval: 30) == 60)
    }

    @Test func aPacedMetricAndALiveListMeetTheirOwnRates() async {
        let sampler = Sampler()
        var demand = MonitorDemand()
        demand.memory = true
        demand.gpu = true
        demand.paces = [.memory: 10]

        let plan = await sampler.plan(for: demand, at: now)

        // Memory was never read, so it is due now; the GPU has no pace, so it reads on every tick.
        #expect(plan.everyTick)
        #expect(plan.dates == [now])
    }

    @Test func pacedMetricsAloneLetTheLoopSleep() async {
        let sampler = Sampler()
        var demand = MonitorDemand()
        demand.memory = true
        demand.paces = [.memory: 10]

        let plan = await sampler.plan(for: demand, at: now)

        #expect(!plan.everyTick)
        #expect(plan.dates.count == 1)
    }

    @Test func sensorsReadEveryFiveSecondsUnlessAListIsOnScreen() async {
        let sampler = Sampler()
        var demand = MonitorDemand()
        demand.sensors = true
        demand.sensorDetail = .summary
        #expect(await !sampler.plan(for: demand, at: now).everyTick)

        demand.sensorDetail = .live
        #expect(await sampler.plan(for: demand, at: now).everyTick)
    }

    @Test func networkAndProcessesReadOnEveryTick() async {
        let sampler = Sampler()
        var demand = MonitorDemand()
        demand.network = true
        #expect(await sampler.plan(for: demand, at: now).everyTick)
        demand = MonitorDemand()
        demand.processes = true
        #expect(await sampler.plan(for: demand, at: now).everyTick)
        #expect(await !sampler.plan(for: MonitorDemand(), at: now).everyTick)
    }

    @Test func aWakeBeforeTheSleepIsKept() async {
        let sleeper = LoopSleeper()
        sleeper.wake()

        // Returns at once; a lost wake would sleep for an hour.
        await sleeper.sleep(for: 3600)
    }

    @Test func aWakeEndsASleepEarly() async {
        let sleeper = LoopSleeper()
        let sleeping = Task { await sleeper.sleep(for: 3600) }
        await Task.yield()
        await Task.yield()

        sleeper.wake()
        await sleeping.value
    }

    @Test func aStoppedLoopDoesNotSleep() async {
        let sleeper = LoopSleeper()
        let stopped = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await sleeper.sleep(for: 3600)
        }
        // Returns at once instead of holding the sleeper for an hour.
        await stopped.value
    }

    @Test func anOldSleepDoesNotClearANewOne() async {
        let sleeper = LoopSleeper()
        let old = Task { await sleeper.sleep(for: 3600) }
        await Task.yield()
        old.cancel()
        let current = Task { await sleeper.sleep(for: 3600) }
        await old.value
        await Task.yield()
        // The new sleep still answers a wake.
        sleeper.wake()
        await current.value
    }
}
