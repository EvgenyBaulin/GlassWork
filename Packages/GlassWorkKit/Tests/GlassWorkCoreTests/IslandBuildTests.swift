import Foundation
@testable import GlassWorkCore
import Testing

struct IslandBuildTests {
    private let now = IslandFixtures.now

    private func entries() throws -> [BuildLogEntry] {
        try BuildManifest.parse(fixture("build-manifest.plist"))
    }

    private func start(at seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    // MARK: Manifest

    @Test func theManifestListsEveryBuildWithItsCounts() throws {
        let all = try entries()
        #expect(all.count == 4)
        let failed = try #require(all.first { $0.id.hasSuffix("2") })
        #expect(failed.status == "E")
        #expect(failed.errors == 3)
        #expect(failed.warnings == 2)
        #expect(failed.name == "Sample")
        #expect(failed.started == start(at: 816_000_100))
    }

    @Test func aFailedBuildHasItsErrorCount() throws {
        let result = try #require(entries().first { $0.id.hasSuffix("2") }?.result)
        #expect(!result.succeeded)
        #expect(result.errors == 3)
        #expect(result.duration == 21)
    }

    @Test func warningsStillSucceed() throws {
        let result = try #require(entries().first { $0.id.hasSuffix("1") }?.result)
        #expect(result.succeeded)
        #expect(result.warnings == 4)
    }

    @Test func theNewestBuildBeingCancelledShowsNothing() throws {
        let run = BuildRun(name: nil, started: start(at: 816_000_090))
        #expect(try BuildManifest.result(for: run, in: entries()) == nil)
    }

    @Test func cancelledAndUnfinishedBuildsHaveNoOutcome() throws {
        let all = try entries()
        #expect(all.first { $0.id.hasSuffix("3") }?.result == nil)
        #expect(all.first { $0.id.hasSuffix("4") }?.result == nil)
    }

    @Test func theTitleNamesABuildWithoutAScheme() {
        let entry = BuildLogEntry(
            id: "x", title: "Build Widgets", scheme: nil, status: "S", errors: 0, warnings: 0,
            started: now, stopped: now
        )
        #expect(entry.name == "Widgets")
    }

    @Test func garbageGivesNothing() {
        #expect(BuildManifest.parse(Data("not a plist".utf8)).isEmpty)
        #expect(BuildManifest.parse(Data()).isEmpty)
    }

    @Test func aRunGetsTheNewestOutcomeThatEndedAfterItBegan() throws {
        // The cancelled build is left out, as it is newer than the failed one.
        let all = try entries().filter { !$0.id.hasSuffix("3") }
        let early = BuildRun(name: nil, started: start(at: 816_000_090))
        #expect(BuildManifest.result(for: early, in: all)?.errors == 3)
        let late = BuildRun(name: nil, started: start(at: 816_000_150))
        #expect(BuildManifest.result(for: late, in: all) == nil)
        #expect(BuildManifest.result(for: early, in: []) == nil)
    }

    // MARK: Processes

    private func processes(_ names: [String]) -> [ProcessUsage] {
        names.enumerated().map { ProcessUsage(pid: Int32($0.offset + 1), name: $0.element, cpu: 1, memory: 1) }
    }

    @Test func buildToolsMeanABuildIsRunning() {
        #expect(BuildProcesses.isBuilding(processes(["launchd", "xcodebuild"])))
        #expect(BuildProcesses.isBuilding(processes(["swift-build"])))
        #expect(!BuildProcesses.isBuilding(processes(["launchd", "Finder"])))
    }

    @Test func theIdleBuildServiceIsNotABuild() {
        #expect(!BuildProcesses.isBuilding(processes(["Xcode", "XCBBuildService"])))
        #expect(BuildProcesses.isBuilding(processes(["XCBBuildService", "swift-frontend"])))
        #expect(BuildProcesses.isBuilding(processes(["SWBBuildService", "clang"])))
        #expect(!BuildProcesses.isBuilding(processes(["swift-frontend"])))
    }

    @Test func theSchemeComesFromTheCommandLine() {
        let line = "xcodebuild -project App.xcodeproj -scheme Sample -configuration Debug build"
        #expect(BuildProcesses.scheme(fromArguments: line) == "Sample")
        #expect(BuildProcesses.scheme(fromArguments: "xcodebuild -target Tool build") == "Tool")
        #expect(BuildProcesses.scheme(fromArguments: "xcodebuild -scheme") == nil)
        #expect(BuildProcesses.scheme(fromArguments: "xcodebuild build") == nil)
    }

    // MARK: Island events

    private func input(_ reading: BuildReading?) -> IslandInput {
        var input = IslandInput()
        input.build = reading
        return input
    }

    private var run: BuildRun {
        BuildRun(name: "Sample", started: now.addingTimeInterval(-30))
    }

    private var failure: BuildResult {
        BuildResult(
            name: "Sample", succeeded: false, errors: 2, warnings: 0,
            started: now.addingTimeInterval(-30), finished: now
        )
    }

    @Test func aRunningBuildStaysWhileItRuns() throws {
        let current = input(.running(run))
        let event = try #require(IslandEventBuilder.events(current: current, previous: current, now: now).first)
        #expect(event.kind == .build)
        #expect(event.expires == nil)
        #expect(event.detail == .build(.running(run)))
        #expect(!event.isTransition)
    }

    @Test func aBuildThatEndsShowsItsResultForAMoment() throws {
        let events = IslandEventBuilder.events(
            current: input(.finished(failure)),
            previous: input(.running(run)),
            now: now
        )
        let event = try #require(events.first)
        #expect(event.detail == .build(.finished(failure)))
        #expect(event.expires == now.addingTimeInterval(IslandEventBuilder.transientDuration))
    }

    @Test func aResultThatWasAlreadyThereShowsNothing() {
        let current = input(.finished(failure))
        #expect(IslandEventBuilder.events(current: current, previous: current, now: now).isEmpty)
        #expect(IslandEventBuilder.events(current: current, previous: nil, now: now).isEmpty)
    }

    @MainActor
    @Test func theResultOutlivesTheNextReadingThenGoes() {
        let store = IslandStore()
        store.update(input: input(.running(run)), now: now.addingTimeInterval(-2))
        #expect(store.queue.events.count == 1)
        store.update(input: input(.finished(failure)), now: now)
        store.update(input: input(.finished(failure)), now: now.addingTimeInterval(2))
        #expect(store.queue.events.first?.detail == .build(.finished(failure)))
        store.update(input: input(.finished(failure)), now: now.addingTimeInterval(5))
        #expect(store.queue.events.isEmpty)
    }

    @MainActor
    @Test func aNewBuildReplacesTheLastResult() {
        let store = IslandStore()
        store.update(input: input(nil), now: now.addingTimeInterval(-2))
        store.update(input: input(.finished(failure)), now: now)
        store.update(input: input(.running(run)), now: now.addingTimeInterval(1))
        #expect(store.queue.events.map(\.detail) == [.build(.running(run))])
    }
}
