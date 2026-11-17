import Foundation
@testable import GlassWorkCore
import Testing

/// The Git widget's own choices: which repositories it lists and what counts as to do.
struct GitWidgetOptionTests {
    private func repository(_ name: String, change: (inout GitStatus) -> Void = { _ in }) -> GitRepository {
        var status = GitStatus()
        status.branch = "main"
        change(&status)
        return GitRepository(path: "/tmp/\(name)", status: status)
    }

    private var reading: GitReading {
        .repositories([
            repository("clean"),
            repository("ahead") { $0.ahead = 2 },
            repository("behind") { $0.behind = 1 },
            repository("changed") { $0.changed = 3 },
            GitRepository(path: "/tmp/gone", problem: .missing),
        ])
    }

    private func toDo(_ rule: GitToDo) -> [String] {
        reading.repositories.filter { $0.needsWork(counting: rule) }.map(\.name)
    }

    @Test func eachRuleCountsItsOwnKindOfWork() {
        #expect(toDo(.uncommitted) == ["changed"])
        #expect(toDo(.unpushed) == ["ahead"])
        #expect(toDo(.both) == ["ahead", "behind", "changed"])
    }

    @Test func theDefaultRuleKeepsWhatTheWidgetAlwaysCounted() {
        #expect(reading.repositories.map { $0.needsWork(counting: .both) } == reading.repositories.map(\.needsWork))
    }

    @Test func theWidgetListsEveryRepositoryUnlessOneIsChosen() {
        let all = WidgetGitOptions()
        #expect(all.shown(in: reading.repositories).count == 5)
        let one = WidgetGitOptions(path: "/tmp/ahead", countsAs: .unpushed)
        #expect(one.shown(in: reading.repositories).map(\.name) == ["ahead"])
        #expect(WidgetGitOptions(path: "/tmp/missing").shown(in: reading.repositories).isEmpty)
    }

    @Test func sharingFollowsTheGitModulesChoice() {
        var settings = GitWidgetSettings()
        settings.source = .shared
        settings.countsAs = .uncommitted
        let chosen = settings.resolved(reading: reading, moduleSelection: "/tmp/behind")
        #expect(chosen == WidgetGitOptions(path: "/tmp/behind", countsAs: .uncommitted))
        // With no choice the module shows the first readable repository, and so does the widget.
        #expect(settings.resolved(reading: reading, moduleSelection: nil).path == "/tmp/clean")
        #expect(settings.resolved(reading: nil, moduleSelection: nil).path == nil)
    }

    @Test func anOwnRepositoryIsUsedOnlyInThatMode() {
        var settings = GitWidgetSettings()
        settings.repositoryPath = "/tmp/changed"
        #expect(settings.ownRepository == nil)
        #expect(settings.resolved(reading: reading, moduleSelection: "/tmp/ahead").path == nil)
        settings.source = .own
        #expect(settings.ownRepository == "/tmp/changed")
        #expect(settings.resolved(reading: reading, moduleSelection: "/tmp/ahead").path == "/tmp/changed")
        settings.repositoryPath = ""
        #expect(settings.ownRepository == nil)
    }

    @Test func theOwnRepositoryIsReadByTheGitModuleToo() {
        var settings = AppSettings()
        settings.widgets.git.source = .own
        settings.widgets.git.repositoryPath = "/tmp/own"
        #expect(DeveloperOptions(settings: settings).gitWidgetRepository == "/tmp/own")
        settings.widgets.git.source = .all
        #expect(DeveloperOptions(settings: settings).gitWidgetRepository == nil)
    }

    @Test func oldSettingsAndSnapshotsReadAsTheDefaults() throws {
        let settings = try JSONDecoder().decode(WidgetSettings.self, from: Data(#"{"refreshSeconds":60}"#.utf8))
        #expect(settings.git == GitWidgetSettings())
        let odd = Data(#"{"git":{"source":"nonsense","countsAs":"unpushed"}}"#.utf8)
        let decoded = try JSONDecoder().decode(WidgetSettings.self, from: odd)
        #expect(decoded.git.source == .all)
        #expect(decoded.git.countsAs == .unpushed)

        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000))
        let plain = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: plain).gitOptions == nil)
        snapshot.gitOptions = WidgetGitOptions(path: "/tmp/x", countsAs: .unpushed)
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(back.gitOptions == snapshot.gitOptions)
    }
}
