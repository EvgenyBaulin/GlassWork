import CoreGraphics
import CoreText
import Foundation
@testable import GlassWorkCore
import ImageIO
import Testing
import UniformTypeIdentifiers
import Vision

/// Black text on white, the way a screen would show it.
private func renderedPNG(lines: [String]) throws -> Data {
    let width = 1200
    let height = 120 * max(lines.count, 1) + 40
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
    ]
    for (index, text) in lines.enumerated() {
        let string = try #require(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
        context.textPosition = CGPoint(x: 40, y: height - 120 * (index + 1))
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
    }
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let target = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(target, image, nil)
    #expect(CGImageDestinationFinalize(target))
    return data as Data
}

/// Recognition stalled the hosted build machines, so it runs on real Macs only.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct TextRecognizerTests {
    @Test func coversBothLanguages() throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        #expect(TextRecognizer.languages.allSatisfy(supported.contains))
    }

    @Test func readsEnglishAndRussian() throws {
        let image = try renderedPNG(lines: ["Quick brown fox", "Съешь этих булок"])
        let text = try TextRecognizer.recognize(image)
        #expect(text.contains("Quick brown fox"))
        #expect(text.contains("Съешь этих булок"))
    }

    @Test func keepsLinesApart() throws {
        let text = try TextRecognizer.recognize(renderedPNG(lines: ["First line", "Second line"]))
        #expect(text.components(separatedBy: "\n").count == 2)
    }

    @Test func findsNothingInABlankImage() throws {
        #expect(try TextRecognizer.recognize(renderedPNG(lines: [])).isEmpty)
    }
}

/// Stands in for the system tool. It writes the picture when told to, like the real one on a selection.
private struct StubSelection: ProcessRunning {
    var picture: Data?
    var failure: ProcessRunnerError?
    var onRun: @Sendable (String, [String]) -> Void = { _, _ in }

    func run(_ executable: String, arguments: [String], timeout _: TimeInterval) async throws -> ProcessOutput {
        onRun(executable, arguments)
        if let failure {
            throw failure
        }
        if let picture, let path = arguments.last {
            try picture.write(to: URL(filePath: path))
        }
        return ProcessOutput(status: 0, stdout: "", stderr: "")
    }
}

struct ScreenTextCaptureTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "GlassWorkCapture-\(UUID().uuidString)")

    private func leftovers() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
    }

    private func capture(_ runner: StubSelection, text: String = "Hello") throws -> ScreenTextCapture {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ScreenTextCapture(runner: runner, directory: directory) { _ in text }
    }

    @Test func aSelectionIsReadAndTheFileIsGone() async throws {
        let result = try await capture(StubSelection(picture: Data([1]))).run()
        #expect(result == .text("Hello"))
        #expect(leftovers().isEmpty)
    }

    @Test func escapeCopiesNothing() async throws {
        let result = try await capture(StubSelection(picture: nil)).run()
        #expect(result == .cancelled)
    }

    @Test func aForgottenSelectionCountsAsCancelled() async throws {
        let runner = StubSelection(failure: .timedOut("screencapture"))
        #expect(try await capture(runner).run() == .cancelled)
    }

    @Test func onlySpacesCountAsNoText() async throws {
        let result = try await capture(StubSelection(picture: Data([1])), text: " \n ").run()
        #expect(result == .noText)
        #expect(leftovers().isEmpty)
    }

    @Test func theFileIsGoneEvenIfReadingFails() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let capture = ScreenTextCapture(runner: StubSelection(picture: Data([1])), directory: directory) { _ in
            throw CocoaError(.fileReadCorruptFile)
        }
        await #expect(throws: CocoaError.self) { try await capture.run() }
        #expect(leftovers().isEmpty)
    }

    @Test func usesTheInteractiveSystemToolSilently() async throws {
        let seen = Seen()
        var runner = StubSelection(picture: Data([1]))
        runner.onRun = { tool, arguments in seen.set(tool, arguments) }
        _ = try await capture(runner).run()
        #expect(seen.tool == "/usr/sbin/screencapture")
        #expect(seen.arguments.prefix(2) == ["-i", "-x"])
        // The picture goes to a file of ours: on the pasteboard it would enter the clipboard history.
        #expect(!seen.arguments.contains("-c"))
    }
}

/// What the stub was called with. A lock, because the stub is called from outside the test's task.
private final class Seen: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var stored: (String, [String]) = ("", [])

    var tool: String {
        lock.withLock { stored.0 }
    }

    var arguments: [String] {
        lock.withLock { stored.1 }
    }

    func set(_ tool: String, _ arguments: [String]) {
        lock.withLock { stored = (tool, arguments) }
    }
}
