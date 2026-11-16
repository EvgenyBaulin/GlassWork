import Foundation

/// Opens only session-state/<uuid>/events.jsonl, never configuration or diagnostic logs.
enum CopilotUsageReader {
    private static let largestFile = 16 * 1024 * 1024

    static func read(home: URL, at now: Date, calendar: Calendar) -> AIToolUsage {
        let root = home.appending(path: ".copilot/session-state")
        let cutoff = calendar.date(byAdding: .day, value: -31, to: now) ?? now
        var sessions: [CopilotSessionUsage] = []
        var unreadable = false
        for file in files(in: root, since: cutoff) {
            guard let data = try? Data(contentsOf: file.url), data.count <= largestFile else {
                unreadable = true
                continue
            }
            if let session = CopilotUsageParser.parse(
                String(decoding: data, as: UTF8.self),
                modifiedAt: file.modifiedAt
            ) {
                sessions.append(session)
            }
        }
        return AIToolUsage(
            tool: .copilotCLI,
            updatedAt: sessions.map(\.updatedAt).max(),
            isUnreadable: unreadable && sessions.isEmpty,
            source: .files,
            spend: sessions.isEmpty ? nil : aggregate(sessions, at: now, calendar: calendar)
        )
    }

    static func aggregate(_ sessions: [CopilotSessionUsage], at now: Date, calendar: Calendar) -> AISpend {
        let today = calendar.startOfDay(for: now)
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? today
        let entries = sessions.flatMap(\.entries).filter { $0.date <= now }
        func total(since start: Date) -> AISpendTotals {
            var result = AISpendTotals()
            for entry in entries where entry.date >= start {
                result.add(entry.totals)
            }
            return result
        }
        return AISpend(
            today: total(since: today),
            last7Days: total(since: week),
            month: total(since: month),
            topModels: CopilotUsageParser.mergedModels(entries.filter { $0.date >= month })
        )
    }

    private static func files(in root: URL, since cutoff: Date) -> [(url: URL, modifiedAt: Date)] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        guard let rootInfo = try? root.resourceValues(forKeys: keys), rootInfo.isSymbolicLink != true,
              let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
        else { return [] }
        return folders.compactMap { folder -> (url: URL, modifiedAt: Date)? in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let info = try? folder.resourceValues(forKeys: keys),
                  info.isDirectory == true, info.isSymbolicLink != true
            else { return nil }
            let file = folder.appending(path: "events.jsonl")
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= largestFile,
                  let modifiedAt = values.contentModificationDate, modifiedAt >= cutoff
            else { return nil }
            return (file, modifiedAt)
        }.sorted {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.url.path < $1.url.path
        }
    }
}
