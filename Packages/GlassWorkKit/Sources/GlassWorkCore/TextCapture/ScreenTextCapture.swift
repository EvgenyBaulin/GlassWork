import Foundation
import Vision

/// Reads text out of an image, on this Mac.
public enum TextRecognizer {
    public static let languages = ["ru-RU", "en-US"]

    /// The text in an image, one line per line found. Empty when there is none.
    public static func recognize(_ image: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: image).perform([request])
        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        return lines.joined(separator: "\n")
    }
}

public enum ScreenTextResult: Equatable, Sendable {
    /// Esc, or the selection was left open for too long.
    case cancelled
    case noText
    case text(String)
}

/// Lets the user pick an area with the system's own selection, then reads the text in it.
public struct ScreenTextCapture: Sendable {
    private static let tool = "/usr/sbin/screencapture"
    /// Selecting takes as long as the user wants, but a forgotten one must not stay forever.
    private static let timeout: TimeInterval = 300

    private let runner: any ProcessRunning
    private let directory: URL
    private let recognize: @Sendable (Data) throws -> String

    public init(
        runner: any ProcessRunning = ProcessRunner(),
        directory: URL = FileManager.default.temporaryDirectory,
        recognize: @escaping @Sendable (Data) throws -> String = TextRecognizer.recognize
    ) {
        self.runner = runner
        self.directory = directory
        self.recognize = recognize
    }

    public func run() async throws -> ScreenTextResult {
        guard let image = try await selectArea() else { return .cancelled }
        let text = try recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .noText : .text(text)
    }

    /// The picture exists on disk only for as long as it takes to read it back.
    private func selectArea() async throws -> Data? {
        let file = directory.appending(path: "GlassWork-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            // -x: no shutter sound. The tool writes nothing when the user presses Esc.
            let arguments = ["-i", "-x", file.path(percentEncoded: false)]
            _ = try await runner.run(Self.tool, arguments: arguments, timeout: Self.timeout)
        } catch ProcessRunnerError.timedOut {
            return nil
        }
        guard let image = try? Data(contentsOf: file), !image.isEmpty else { return nil }
        return image
    }
}
