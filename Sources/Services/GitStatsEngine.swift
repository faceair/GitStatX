import Foundation
import SwiftData

class GitStatsEngine {
    let project: Project
    let repository: GitRepository
    let context: ModelContext

    private typealias AuthorAgg = (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)
    private typealias FileAgg = (commits: Int, added: Int, removed: Int)

    private var statsCache: StatsCache?
    private var cacheURL: URL {
        URL(fileURLWithPath: project.statsPath).appendingPathComponent("stats_cache.json")
    }

    struct ProgressUpdate {
        enum Stage {
            case scanning
            case processing
        }
        let stage: Stage
        let processed: Int
        let total: Int
    }

    init(project: Project, context: ModelContext) {
        self.project = project
        self.context = context
        self.repository = GitRepository(path: project.path!)!
    }

    func generateStats(forceFullRebuild: Bool = false, progress: ((ProgressUpdate) -> Void)? = nil) async throws -> String {
        print("🚀 GitStatsEngine.generateStats() started")
        let generatedAt = Date()

        if !forceFullRebuild,
           let last = project.lastGeneratedCommit,
           let head = repository.currentCommitHash,
           last == head,
           project.statsExists {
            print("⚡️ Stats up-to-date, skipping regeneration")
            return project.statsPath
        }

        await MainActor.run {
            project.isGeneratingStats = true
            try? context.save()
        }

        defer {
            print("🏁 GitStatsEngine.generateStats() finished")
            Task { @MainActor in
                project.isGeneratingStats = false
                project.lastGeneratedCommit = repository.currentCommitHash
                try? self.context.save()
            }
        }

        statsCache = forceFullRebuild ? nil : loadStatsCache()
        if let cache = statsCache, cache.hasLineBreakdown == false {
            statsCache = nil
        }
        let lastCachedCommit = statsCache?.lastCommit ?? project.lastGeneratedCommit
        // 判断是否需要增量处理
        let isIncremental = !forceFullRebuild &&
                           lastCachedCommit != nil &&
                           project.statsExists &&
                           statsCache != nil

        let sinceCommit: String? = isIncremental ? lastCachedCommit : nil

        let totalStart = Date()
        print("📊 Fetching commits\(isIncremental ? " (incremental since \(sinceCommit!))" : "")...")
        progress?(ProgressUpdate(stage: .scanning, processed: 0, total: 0))
        await MainActor.run {
            project.progressStage = "scanning"
            project.progressProcessed = 0
            project.progressTotal = 0
        }

        let fetchStart = Date()
        let parsedCommits = repository.getCommitsWithNumstat(since: sinceCommit) { processed, total in
            progress?(ProgressUpdate(stage: .scanning, processed: processed, total: total))
            Task { @MainActor in
                self.project.progressStage = "scanning"
                self.project.progressProcessed = processed
                self.project.progressTotal = total
            }
        }
        let fetchDuration = Date().timeIntervalSince(fetchStart)

        print("✅ Found \(parsedCommits.count) commits")

        // 如果是增量处理且没有新提交，直接返回
        if isIncremental && parsedCommits.isEmpty {
            print("⚡️ No new commits since last generation")
            return project.statsPath
        }

        progress?(ProgressUpdate(stage: .processing, processed: 0, total: parsedCommits.count))
        await MainActor.run {
            project.progressStage = "processing"
            project.progressProcessed = 0
            project.progressTotal = parsedCommits.count
        }

        let initDataStart = Date()
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

        if let cache = statsCache {
            totalCommits = cache.totalCommits
            totalLinesAdded = cache.totalLinesAdded
            totalLinesRemoved = cache.totalLinesRemoved
            currentLoc = cache.currentLoc
            fileSet = Set(cache.fileSet)
            filesByDate = cache.filesByDate
            locByDate = cache.locByDate
            linesAddedByYear = cache.linesAddedByYear
            linesRemovedByYear = cache.linesRemovedByYear
            linesAddedByYearMonth = cache.linesAddedByYearMonth
            linesRemovedByYearMonth = cache.linesRemovedByYearMonth
            authorStats = cache.authorStats.mapValues {
                (name: $0.name, email: $0.email, commits: $0.commits, added: $0.added, removed: $0.removed, firstDate: $0.firstDate, lastDate: $0.lastDate)
            }
            fileStats = cache.fileStats.mapValues { (commits: $0.commits, added: $0.added, removed: $0.removed) }
        }
        let initDataDuration = Date().timeIntervalSince(initDataStart)

        print("📈 Aggregating results...")
        let aggregateStart = Date()
        struct PartialAggregate {
            var totalCommits: Int = 0
            var totalAdded: Int = 0
            var totalRemoved: Int = 0
            var authorStats: [String: AuthorAgg] = [:]
            var fileStats: [String: FileAgg] = [:]
            var dailyNetLoc: [String: Int] = [:]
            var firstSeenDayForFile: [String: String] = [:]
            var linesAddedByYear: [String: Int] = [:]
            var linesRemovedByYear: [String: Int] = [:]
            var linesAddedByYearMonth: [String: Int] = [:]
            var linesRemovedByYearMonth: [String: Int] = [:]
        }

        let workerCount = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 2, parsedCommits.count))
        let chunkSize = (parsedCommits.count + workerCount - 1) / workerCount
        var partials = Array(repeating: PartialAggregate(), count: workerCount)
        let progressQueue = DispatchQueue(label: "com.gitstatx.progress")

        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let start = worker * chunkSize
            let end = min(start + chunkSize, parsedCommits.count)
            guard start < end else { return }

            var partial = PartialAggregate()
            let calendar = Calendar(identifier: .gregorian)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]

            for index in start..<end {
                let entry = parsedCommits[index]
                partial.totalCommits += 1
                let commit = entry.commit
                let dayKey = formatter.string(from: calendar.startOfDay(for: commit.authorDate))

                let authorKey = "\(commit.authorName) <\(commit.authorEmail)>"
                if partial.authorStats[authorKey] == nil {
                    partial.authorStats[authorKey] = (commit.authorName, commit.authorEmail, 0, 0, 0, commit.authorDate, commit.authorDate)
                }

                var stats = partial.authorStats[authorKey]!
                let commitAdded = entry.numstats.reduce(0) { $0 + $1.added }
                let commitRemoved = entry.numstats.reduce(0) { $0 + $1.removed }
                let dateComponents = calendar.dateComponents([.year, .month], from: commit.authorDate)
                if let year = dateComponents.year {
                    let yearKey = String(format: "%04d", year)
                    partial.linesAddedByYear[yearKey, default: 0] += commitAdded
                    partial.linesRemovedByYear[yearKey, default: 0] += commitRemoved
                    if let month = dateComponents.month {
                        let ymKey = String(format: "%04d-%02d", year, month)
                        partial.linesAddedByYearMonth[ymKey, default: 0] += commitAdded
                        partial.linesRemovedByYearMonth[ymKey, default: 0] += commitRemoved
                    }
                }
                stats.commits += 1
                stats.added += commitAdded
                stats.removed += commitRemoved
                stats.firstDate = stats.firstDate.map { min($0, commit.authorDate) } ?? commit.authorDate
                stats.lastDate = stats.lastDate.map { max($0, commit.authorDate) } ?? commit.authorDate
                partial.authorStats[authorKey] = stats

                partial.totalAdded += commitAdded
                partial.totalRemoved += commitRemoved
                partial.dailyNetLoc[dayKey, default: 0] += commitAdded - commitRemoved

                for numstat in entry.numstats {
                    var fstats = partial.fileStats[numstat.path] ?? (0, 0, 0)
                    fstats.commits += 1
                    fstats.added += numstat.added
                    fstats.removed += numstat.removed
                    partial.fileStats[numstat.path] = fstats

                    if partial.firstSeenDayForFile[numstat.path] == nil {
                        partial.firstSeenDayForFile[numstat.path] = dayKey
                    } else if let existingDay = partial.firstSeenDayForFile[numstat.path], dayKey < existingDay {
                        partial.firstSeenDayForFile[numstat.path] = dayKey
                    }
                }
            }

            partials[worker] = partial
        }

        func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
            switch (lhs, rhs) {
            case let (l?, r?):
                return min(l, r)
            case (nil, let r?):
                return r
            case (let l?, nil):
                return l
            default:
                return nil
            }
        }

        func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
            switch (lhs, rhs) {
            case let (l?, r?):
                return max(l, r)
            case (nil, let r?):
                return r
            case (let l?, nil):
                return l
            default:
                return nil
            }
        }

        var dailyNetLoc: [String: Int] = [:]
        var firstSeenDayForFile: [String: String] = [:]
        var processedChunks = 0

        for partial in partials {
            totalCommits += partial.totalCommits
            totalLinesAdded += partial.totalAdded
            totalLinesRemoved += partial.totalRemoved

            for (key, stats) in partial.authorStats {
                if let existing = authorStats[key] {
                    authorStats[key] = (
                        name: existing.name,
                        email: existing.email,
                        commits: existing.commits + stats.commits,
                        added: existing.added + stats.added,
                        removed: existing.removed + stats.removed,
                        firstDate: minDate(existing.firstDate, stats.firstDate),
                        lastDate: maxDate(existing.lastDate, stats.lastDate)
                    )
                } else {
                    authorStats[key] = stats
                }
            }

            for (path, stats) in partial.fileStats {
                if let existing = fileStats[path] {
                    fileStats[path] = (
                        commits: existing.commits + stats.commits,
                        added: existing.added + stats.added,
                        removed: existing.removed + stats.removed
                    )
                } else {
                    fileStats[path] = stats
                }
            }

            for (year, added) in partial.linesAddedByYear {
                linesAddedByYear[year, default: 0] += added
            }
            for (year, removed) in partial.linesRemovedByYear {
                linesRemovedByYear[year, default: 0] += removed
            }
            for (period, added) in partial.linesAddedByYearMonth {
                linesAddedByYearMonth[period, default: 0] += added
            }
            for (period, removed) in partial.linesRemovedByYearMonth {
                linesRemovedByYearMonth[period, default: 0] += removed
            }

            for (day, delta) in partial.dailyNetLoc {
                dailyNetLoc[day, default: 0] += delta
            }

            for (path, day) in partial.firstSeenDayForFile {
                if fileSet.contains(path) {
                    continue
                }
                if let existingDay = firstSeenDayForFile[path] {
                    if day < existingDay {
                        firstSeenDayForFile[path] = day
                    }
                } else {
                    firstSeenDayForFile[path] = day
                }
            }
        }

        var clampedProcessed = parsedCommits.count
        progressQueue.sync {
            processedChunks += 1
            let processedSoFar = processedChunks * chunkSize
            clampedProcessed = min(processedSoFar, parsedCommits.count)
        }
        progress?(ProgressUpdate(stage: .processing, processed: clampedProcessed, total: parsedCommits.count))
        Task { @MainActor in
            self.project.progressStage = "processing"
            self.project.progressProcessed = clampedProcessed
            self.project.progressTotal = parsedCommits.count
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

        progress?(ProgressUpdate(stage: .processing, processed: parsedCommits.count, total: parsedCommits.count))
        Task { @MainActor in
            self.project.progressStage = "done"
            self.project.progressProcessed = parsedCommits.count
            self.project.progressTotal = parsedCommits.count
        }
        let aggregateDuration = Date().timeIntervalSince(aggregateStart)

        let snapshotStart = Date()
        let snapshot: SnapshotStats?
        if let lastTreeHash = parsedCommits.last?.commit.treeHash {
            let snapshotStats = repository.calculateSnapshotStats(treeHash: lastTreeHash)
            snapshot = SnapshotStats(
                fileCount: snapshotStats.files,
                lineCount: snapshotStats.lines,
                extensions: snapshotStats.extensions,
                totalSize: snapshotStats.size
            )
        } else {
            snapshot = nil
        }
        let snapshotDuration = Date().timeIntervalSince(snapshotStart)

        let allCommitsStart = Date()
        let commits = repository.getAllCommits()
        let allCommitsDuration = Date().timeIntervalSince(allCommitsStart)

        let reportStart = Date()
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
            commitsByTimezone: Self.calculateTimezone(commits: commits),
            tags: Self.calculateTags(repository: repository, commits: commits)
        )
        let reportDuration = Date().timeIntervalSince(reportStart)
        let totalDuration = Date().timeIntervalSince(totalStart)

        func fmt(_ t: TimeInterval) -> String { String(format: "%.3fs", t) }
        print("⏱ Timing => fetch: \(fmt(fetchDuration)), init: \(fmt(initDataDuration)), aggregate: \(fmt(aggregateDuration)), snapshot: \(fmt(snapshotDuration)), getAll: \(fmt(allCommitsDuration)), report: \(fmt(reportDuration)), total: \(fmt(totalDuration))")

        let cacheToSave = StatsCache(
            lastCommit: repository.currentCommitHash,
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
        tags: [TagStats]
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
            tags: tags
        )

        return statsPath
    }

    private func loadStatsCache() -> StatsCache? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StatsCache.self, from: data)
        } catch {
            print("⚠️ Failed to load stats cache: \(error)")
            return nil
        }
    }

    private func saveStatsCache(_ cache: StatsCache) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("⚠️ Failed to save stats cache: \(error)")
        }
    }

    private static func calculateTimezone(commits: [GitCommit]) -> [Int: Int] {
        var buckets: [Int: Int] = [:]
        for commit in commits {
            let offset = commit.authorTimeZoneOffsetMinutes ?? 0
            buckets[offset, default: 0] += 1
        }
        return buckets
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

        var result: [TagStats] = []
        var previousTag: String?
        for tag in sorted {
            let shortlog = repository.getShortlogBetween(tag: tag.name, previousTag: previousTag)
            let commitsForTag = shortlog.reduce(0) { $0 + $1.commits }
            var authors: [String: Int] = [:]
            for entry in shortlog {
                authors[entry.author, default: 0] += entry.commits
            }
            result.append(TagStats(name: tag.name, date: tag.date, commits: commitsForTag, authors: authors))
            previousTag = tag.name
        }

        return result
    }

}
