import CoreGraphics
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

    /// Reads a tiny picture so Vision loads its model now, not on the first real selection.
    /// Blocks for as long as the model takes to load, so call it off the main actor.
    public static func warmUp() {
        guard let image = warmUpImage() else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
    }

    private static func warmUpImage() -> CGImage? {
        let width = 160
        let height = 48
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        // Bars of about the height of text: enough for the model to run, nothing to read.
        for index in 0 ..< 6 {
            context.fill(CGRect(x: 12 + index * 24, y: 14, width: 10, height: 20))
        }
        return context.makeImage()
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

    /// - Parameter onRecognizing: Called once the area is picked, before the text is read.
    public func run(onRecognizing: @MainActor @Sendable () -> Void = {}) async throws -> ScreenTextResult {
        guard let image = try await selectArea() else { return .cancelled }
        await onRecognizing()
        // Reading takes a moment and must not hold up the interface, whatever this is called from.
        let recognize = recognize
        let read = try await Task.detached(priority: .userInitiated) { try recognize(image) }.value
        let text = read.trimmingCharacters(in: .whitespacesAndNewlines)
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
