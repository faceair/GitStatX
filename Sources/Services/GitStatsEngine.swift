import Foundation
import SwiftData

class GitStatsEngine {
    let project: Project
    let repository: GitRepository
    let context: ModelContext

    private typealias AuthorAgg = (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)
    private typealias FileAgg = (commits: Int, added: Int, removed: Int)

    private var generatedCommitHash: String?
    private var cacheURL: URL {
        URL(fileURLWithPath: project.statsPath).appendingPathComponent("stats_cache.json")
    }

    init(project: Project, context: ModelContext) {
        self.project = project
        self.context = context
        self.repository = GitRepository(path: project.path!)!
    }

    func generateStats(forceFullRebuild: Bool = false) async throws -> String {
        let generatedAt = Date()

        if !forceFullRebuild,
           let last = project.lastGeneratedCommit,
           let head = repository.currentCommitHash,
           last == head,
           project.statsExists {
            return project.statsPath
        }

        await MainActor.run {
            project.isGeneratingStats = true
            project.progressStage = "Preparing"
            project.progressDetail = nil
            try? context.save()
        }

        defer {
            let commitToRecord = generatedCommitHash ?? repository.currentCommitHash
            Task { @MainActor in
                project.isGeneratingStats = false
                project.progressStage = nil
                project.progressDetail = nil
                project.lastGeneratedCommit = commitToRecord
                NotificationCenter.default.post(name: .gitStatsGenerationCompleted, object: project.identifier)
                try? self.context.save()
            }
        }

        setProgress(stage: "Fetching commits", detail: nil)

        var lastProgressCommit = 0
        let parsedCommits = repository.getCommitsWithNumstat { processed, total in
            if processed != 1 && processed - lastProgressCommit < 500 {
                if let total = total, processed == total {
                    // final progress update
                } else {
                    return
                }
            }
            lastProgressCommit = processed
            if let total = total, total > 0 {
                let percent = Double(processed) * 100.0 / Double(total)
                self.updateProgressDetail(String(format: "Fetching commits %d/%d (%.1f%%)", processed, total, percent))
            } else {
                self.updateProgressDetail("Fetching commits \(processed)")
            }
        }

        generatedCommitHash = parsedCommits.last?.commit.hash ?? repository.currentCommitHash

        var authorStats: [String: AuthorAgg] = [:]
        var fileStats: [String: FileAgg] = [:]
        var fileSet = Set<String>()
        var currentLoc = 0
        var filesByDate: [String: Int] = [:]
        var locByDate: [String: Int] = [:]
        var totalCommits = 0
        var totalLinesAdded = 0
        var totalLinesRemoved = 0
        var linesAddedByYear: [String: Int] = [:]
        var linesRemovedByYear: [String: Int] = [:]
        var linesAddedByYearMonth: [String: Int] = [:]
        var linesRemovedByYearMonth: [String: Int] = [:]
        setProgress(stage: "Aggregating results", detail: nil)
        Self.aggregateCommits(
            parsedCommits: parsedCommits,
            authorStats: &authorStats,
            fileStats: &fileStats,
            fileSet: &fileSet,
            filesByDate: &filesByDate,
            locByDate: &locByDate,
            linesAddedByYear: &linesAddedByYear,
            linesRemovedByYear: &linesRemovedByYear,
            linesAddedByYearMonth: &linesAddedByYearMonth,
            linesRemovedByYearMonth: &linesRemovedByYearMonth,
            totalCommits: &totalCommits,
            totalLinesAdded: &totalLinesAdded,
            totalLinesRemoved: &totalLinesRemoved,
            currentLoc: &currentLoc
        )

        let commits = parsedCommits.map { $0.commit }

        setProgress(stage: "Building snapshot", detail: nil)
        let snapshot = Self.buildSnapshot(
            fileStats: fileStats,
            fileSet: fileSet,
            currentLoc: currentLoc
        )

        setProgress(stage: "Calculating timezone", detail: nil)
        let commitsByTimezone = Self.calculateTimezone(commits: commits)

        setProgress(stage: "Calculating tags", detail: nil)
        let tags = Self.calculateTags(repository: repository, commits: commits)

        let hourTimezoneLabel = HTMLReportGenerator.hourTimezoneLabel()
        setProgress(stage: "Generating report", detail: nil)
        let statsPath = try await generateHTMLReport(
            totalCommits: totalCommits,
            totalLinesAdded: totalLinesAdded,
            totalLinesRemoved: totalLinesRemoved,
            authors: authorStats,
            commits: commits,
            files: fileStats,
            snapshot: snapshot,
            filesByDate: filesByDate,
            locByDate: locByDate,
            linesAddedByYear: linesAddedByYear,
            linesRemovedByYear: linesRemovedByYear,
            linesAddedByYearMonth: linesAddedByYearMonth,
            linesRemovedByYearMonth: linesRemovedByYearMonth,
            generatedAt: generatedAt,
            commitsByTimezone: commitsByTimezone,
            tags: tags,
            hourTimezoneLabel: hourTimezoneLabel
        )

        let cacheToSave = StatsCache(
            lastCommit: generatedCommitHash ?? repository.currentCommitHash,
            totalCommits: totalCommits,
            totalLinesAdded: totalLinesAdded,
            totalLinesRemoved: totalLinesRemoved,
            currentLoc: currentLoc,
            fileSet: Array(fileSet),
            filesByDate: filesByDate,
            locByDate: locByDate,
            authorStats: authorStats.mapValues {
                StatsCache.Author(
                    name: $0.name,
                    email: $0.email,
                    commits: $0.commits,
                    added: $0.added,
                    removed: $0.removed,
                    firstDate: $0.firstDate,
                    lastDate: $0.lastDate
                )
            },
            fileStats: fileStats.mapValues { StatsCache.File(commits: $0.commits, added: $0.added, removed: $0.removed) },
            linesAddedByYear: linesAddedByYear,
            linesRemovedByYear: linesRemovedByYear,
            linesAddedByYearMonth: linesAddedByYearMonth,
            linesRemovedByYearMonth: linesRemovedByYearMonth,
            hasLineBreakdown: true
        )
        saveStatsCache(cacheToSave)

        return statsPath
    }

    private func setProgress(stage: String, detail: String?) {
        Task { @MainActor in
            project.progressStage = stage
            project.progressDetail = detail
        }
    }

    private func updateProgressDetail(_ detail: String?) {
        Task { @MainActor in
            project.progressDetail = detail
        }
    }

    private static func aggregateCommits(
        parsedCommits: [GitRepository.ParsedCommitNumstat],
        authorStats: inout [String: AuthorAgg],
        fileStats: inout [String: FileAgg],
        fileSet: inout Set<String>,
        filesByDate: inout [String: Int],
        locByDate: inout [String: Int],
        linesAddedByYear: inout [String: Int],
        linesRemovedByYear: inout [String: Int],
        linesAddedByYearMonth: inout [String: Int],
        linesRemovedByYearMonth: inout [String: Int],
        totalCommits: inout Int,
        totalLinesAdded: inout Int,
        totalLinesRemoved: inout Int,
        currentLoc: inout Int
    ) {
        var dailyNetLoc: [String: Int] = [:]
        var firstSeenDayForFile: [String: String] = [:]

        let calendar = Calendar(identifier: .gregorian)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        for entry in parsedCommits {
            totalCommits += 1
            let commit = entry.commit
            let dayKey = formatter.string(from: calendar.startOfDay(for: commit.authorDate))

            let commitAdded = entry.numstats.reduce(0) { $0 + $1.added }
            let commitRemoved = entry.numstats.reduce(0) { $0 + $1.removed }

            let authorKey = "\(commit.authorName) <\(commit.authorEmail)>"
            var stats = authorStats[authorKey] ?? (commit.authorName, commit.authorEmail, 0, 0, 0, commit.authorDate, commit.authorDate)
            stats.commits += 1
            stats.added += commitAdded
            stats.removed += commitRemoved
            stats.firstDate = stats.firstDate.map { min($0, commit.authorDate) } ?? commit.authorDate
            stats.lastDate = stats.lastDate.map { max($0, commit.authorDate) } ?? commit.authorDate
            authorStats[authorKey] = stats

            totalLinesAdded += commitAdded
            totalLinesRemoved += commitRemoved
            dailyNetLoc[dayKey, default: 0] += commitAdded - commitRemoved

            let dateComponents = calendar.dateComponents([.year, .month], from: commit.authorDate)
            if let year = dateComponents.year {
                let yearKey = String(format: "%04d", year)
                linesAddedByYear[yearKey, default: 0] += commitAdded
                linesRemovedByYear[yearKey, default: 0] += commitRemoved
                if let month = dateComponents.month {
                    let ymKey = String(format: "%04d-%02d", year, month)
                    linesAddedByYearMonth[ymKey, default: 0] += commitAdded
                    linesRemovedByYearMonth[ymKey, default: 0] += commitRemoved
                }
            }

            for numstat in entry.numstats {
                var fstats = fileStats[numstat.path] ?? (0, 0, 0)
                fstats.commits += 1
                fstats.added += numstat.added
                fstats.removed += numstat.removed
                fileStats[numstat.path] = fstats

                guard !fileSet.contains(numstat.path) else { continue }
                if let existingDay = firstSeenDayForFile[numstat.path] {
                    if dayKey < existingDay {
                        firstSeenDayForFile[numstat.path] = dayKey
                    }
                } else {
                    firstSeenDayForFile[numstat.path] = dayKey
                }
            }
        }

        if !dailyNetLoc.isEmpty {
            let sortedDays = dailyNetLoc.keys.sorted()
            for day in sortedDays {
                currentLoc = max(0, currentLoc + dailyNetLoc[day]!)
                locByDate[day] = currentLoc
            }
        }

        if !firstSeenDayForFile.isEmpty {
            var currentFileCount = fileSet.count
            var newFilesByDay: [String: Int] = [:]
            for (_, day) in firstSeenDayForFile {
                newFilesByDay[day, default: 0] += 1
            }

            for day in newFilesByDay.keys.sorted() {
                currentFileCount += newFilesByDay[day] ?? 0
                filesByDate[day] = currentFileCount
            }
            fileSet.formUnion(firstSeenDayForFile.keys)
        }

    }

    private static func buildSnapshot(
        fileStats: [String: (commits: Int, added: Int, removed: Int)],
        fileSet: Set<String>,
        currentLoc: Int
    ) -> SnapshotStats {
        var extStats: [String: (files: Int, lines: Int)] = [:]
        for (path, stats) in fileStats {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            let key = ext.isEmpty ? "unknown" : ext
            var entry = extStats[key] ?? (0, 0)
            entry.files += 1
            let net = stats.added - stats.removed
            if net > 0 { entry.lines += net }
            extStats[key] = entry
        }
        return SnapshotStats(
            fileCount: fileSet.count,
            lineCount: currentLoc,
            extensions: extStats
        )
    }

    private static func calculateTags(repository: GitRepository, commits: [GitCommit]) -> [TagStats] {
        let tags = repository.getTags()
        guard !tags.isEmpty else { return [] }

        let sorted = tags.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.name < rhs.name
            }
        }

        let calendar = Calendar(identifier: .gregorian)
        let commitCount = commits.count
        let indexByHash = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($0.element.hash, $0.offset) })
        let parentsByIndex: [[String]] = commits.map { $0.parentHashes }

        var result: [TagStats] = []
        var previousReachable = Array(repeating: false, count: commitCount)
        var previousDate: Date?

        for tag in sorted {
            guard let startIndex = indexByHash[tag.commitHash] else { continue }

            var stack: [Int] = [startIndex]
            var reachable = Array(repeating: false, count: commitCount)
            var authors: [String: Int] = [:]
            var commitTotal = 0

            while let idx = stack.popLast() {
                if reachable[idx] { continue }
                reachable[idx] = true

                for parentHash in parentsByIndex[idx] {
                    if let parentIndex = indexByHash[parentHash] {
                        stack.append(parentIndex)
                    }
                }

                if previousReachable[idx] {
                    continue
                }

                commitTotal += 1
                let commit = commits[idx]
                authors[commit.authorName, default: 0] += 1
            }

            let daysSincePrevious: Int?
            if let currentDate = tag.date, let prevDate = previousDate {
                let startCurrent = calendar.startOfDay(for: currentDate)
                let startPrev = calendar.startOfDay(for: prevDate)
                let delta = calendar.dateComponents([.day], from: startPrev, to: startCurrent).day ?? 0
                daysSincePrevious = max(0, delta)
            } else {
                daysSincePrevious = nil
            }

            result.append(
                TagStats(
                    name: tag.name,
                    date: tag.date,
                    commits: commitTotal,
                    authors: authors,
                    authorCount: authors.count,
                    daysSincePrevious: daysSincePrevious
                )
            )

            previousReachable = reachable
            if let date = tag.date {
                previousDate = date
            }
        }

        return result
    }

    private static func calculateTimezone(commits: [GitCommit]) -> [Int: Int] {
        var buckets: [Int: Int] = [:]
        for commit in commits {
            let offset = commit.authorTimeZoneOffsetMinutes ?? 0
            buckets[offset, default: 0] += 1
        }
        return buckets
    }

    private func generateHTMLReport(
        totalCommits: Int,
        totalLinesAdded: Int,
        totalLinesRemoved: Int,
        authors: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)],
        commits: [GitCommit],
        files: [String: (commits: Int, added: Int, removed: Int)],
        snapshot: SnapshotStats?,
        filesByDate: [String: Int],
        locByDate: [String: Int],
        linesAddedByYear: [String: Int],
        linesRemovedByYear: [String: Int],
        linesAddedByYearMonth: [String: Int],
        linesRemovedByYearMonth: [String: Int],
        generatedAt: Date,
        commitsByTimezone: [Int: Int],
        tags: [TagStats],
        hourTimezoneLabel: String
    ) async throws -> String {
        let statsPath = project.statsPath
        let reportGenerator = HTMLReportGenerator(statsPath: statsPath)

        try reportGenerator.generateReport(
            projectName: project.displayName,
            totalCommits: totalCommits,
            totalAuthors: authors.count,
            totalFiles: snapshot?.fileCount ?? files.count,
            totalLinesOfCode: snapshot?.lineCount ?? 0,
            totalLinesAdded: totalLinesAdded,
            totalLinesRemoved: totalLinesRemoved,
            authors: authors,
            commits: commits,
            files: files,
            snapshot: snapshot,
            filesByDate: filesByDate,
            locByDate: locByDate,
            linesAddedByYear: linesAddedByYear,
            linesRemovedByYear: linesRemovedByYear,
            linesAddedByYearMonth: linesAddedByYearMonth,
            linesRemovedByYearMonth: linesRemovedByYearMonth,
            generatedAt: generatedAt,
            commitsByTimezone: commitsByTimezone,
            tags: tags,
            hourTimezoneLabel: hourTimezoneLabel
        )

        return statsPath
    }

    private func saveStatsCache(_ cache: StatsCache) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
        }
    }

}

extension Notification.Name {
    static let gitStatsGenerationCompleted = Notification.Name("GitStatsGenerationCompleted")
}
