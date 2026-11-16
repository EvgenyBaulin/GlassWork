import Foundation

/// Rules for what the app hands to the island, kept apart from the listeners so they can be tested.
public enum IslandFeedRules {
    /// How many finished files travel along, so the island can show them as done.
    public static let finishedLimit = 10
    /// Below this, a brightness difference is sensor jitter or an ambient-light step, not a change worth showing.
    public static let brightnessThreshold = 0.02

    /// The Downloads folder as the island wants it: files in progress, and the newest finished ones.
    ///
    /// A browser renames "report.pdf.crdownload" to "report.pdf" when it finishes, so a partial file keeps the path
    /// of its final name; otherwise a finished file could never be matched with its earlier download.
    public static func downloads(from files: [DockFile]) -> [DockFile] {
        let active = files.filter(\.isDownloading).map { file -> DockFile in
            var file = file
            file.path = partialFree(file.path)
            return file
        }
        let activePaths = Set(active.map(\.path))
        let finished = DockFiles.sorted(files.filter { !$0.isDownloading && !activePaths.contains($0.path) })
        return DockFiles.sorted(active) + finished.prefix(finishedLimit)
    }

    /// True when a reading is worth passing on: the first one, one that appears or vanishes, or a real step.
    public static func brightnessChanged(from old: Double?, to new: Double?) -> Bool {
        switch (old, new) {
        case let (old?, new?): abs(old - new) >= brightnessThreshold
        case (nil, nil): false
        default: true
        }
    }

    private static func partialFree(_ path: String) -> String {
        DockFiles.isPartial(name: path) ? (path as NSString).deletingPathExtension : path
    }
}
