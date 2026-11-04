import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

struct TextCaptureNoticeTests {
    @Test func countsCharactersInTheMessage() {
        #expect(TextCaptureNotice.copied(characters: 1).title.contains("1"))
        #expect(TextCaptureNotice.copied(characters: 42).title.contains("42"))
    }

    @Test func onlyThePermissionMessageExplainsAnything() {
        #expect(TextCaptureNotice.noText.detail == nil)
        #expect(TextCaptureNotice.needsScreenRecording.detail != nil)
        #expect(TextCaptureNotice.needsScreenRecording.duration > TextCaptureNotice.noText.duration)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct TextCaptureHUDSnapshotTests {
    @Test(arguments: [true, false])
    func copied(dark: Bool) {
        snapshotPanel(TextCaptureHUD(notice: .copied(characters: 42)), name: "copied", dark: dark)
    }

    @Test(arguments: [true, false])
    func noText(dark: Bool) {
        snapshotPanel(TextCaptureHUD(notice: .noText), name: "no-text", dark: dark)
    }

    @Test(arguments: [true, false])
    func needsPermission(dark: Bool) {
        snapshotPanel(TextCaptureHUD(notice: .needsScreenRecording), name: "permission", dark: dark)
    }
}
