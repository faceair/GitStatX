import Foundation
import SwiftData

class GitStatsEngine {
    let project: Project
    let repository: GitRepository
    let context: ModelContext

    private typealias AuthorAgg = (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)
    private typealias FileAgg = (commits: Int, added: Int, removed: Int)

    private var statsCache: StatsCache?
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
        print("🚀 GitStatsEngine.generateStats() started")
        let generatedAt = Date()
        func fmt(_ t: TimeInterval) -> String { String(format: "%.3fs", t) }

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
            let commitToRecord = generatedCommitHash ?? repository.currentCommitHash
            Task { @MainActor in
                project.isGeneratingStats = false
                project.lastGeneratedCommit = commitToRecord
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

        let fetchStart = Date()
        let parsedCommits = repository.getCommitsWithNumstat(since: sinceCommit)
        let fetchDuration = Date().timeIntervalSince(fetchStart)

        generatedCommitHash = parsedCommits.last?.commit.hash ?? lastCachedCommit ?? repository.currentCommitHash
        print("✅ Found \(parsedCommits.count) commits")
        print("⏱ Fetch stage finished in \(fmt(fetchDuration))")

        // 如果是增量处理且没有新提交，直接返回
        if isIncremental && parsedCommits.isEmpty {
            print("⚡️ No new commits since last generation")
            return project.statsPath
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
        let aggregateDuration = Self.aggregateCommits(
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

        print("⏱ Aggregate stage finished in \(fmt(aggregateDuration))")

        let commits = parsedCommits.map { $0.commit }

        let snapshotStart = Date()
        let snapshot = Self.buildSnapshot(
            fileStats: fileStats,
            fileSet: fileSet,
            currentLoc: currentLoc
        )
        let snapshotDuration = Date().timeIntervalSince(snapshotStart)
        print("⏱ Snapshot stage finished in \(fmt(snapshotDuration))")

        let timezoneStart = Date()
        let commitsByTimezone = Self.calculateTimezone(commits: commits)
        let timezoneDuration = Date().timeIntervalSince(timezoneStart)
        print("⏱ Timezone stage finished in \(fmt(timezoneDuration))")

        let tagsStart = Date()
        let tags = Self.calculateTags(repository: repository, commits: commits)
        let tagsDuration = Date().timeIntervalSince(tagsStart)
        print("⏱ Tags stage finished in \(fmt(tagsDuration))")

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
            commitsByTimezone: commitsByTimezone,
            tags: tags
        )
        let reportDuration = Date().timeIntervalSince(reportStart)
        let totalDuration = Date().timeIntervalSince(totalStart)

        print("⏱ Timing => fetch: \(fmt(fetchDuration)), init: \(fmt(initDataDuration)), aggregate: \(fmt(aggregateDuration)), snapshot: \(fmt(snapshotDuration)), tz: \(fmt(timezoneDuration)), tags: \(fmt(tagsDuration)), report: \(fmt(reportDuration)), total: \(fmt(totalDuration))")

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
    ) -> TimeInterval {
        let aggregateStart = Date()
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

        return Date().timeIntervalSince(aggregateStart)
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

}
