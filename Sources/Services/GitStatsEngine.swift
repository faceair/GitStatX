import Foundation
import SwiftData

class GitStatsEngine {
    let project: Project
    let repository: GitRepository
    let context: ModelContext

    // 增量处理缓存
    private var existingTotalCommits: Int = 0
    private var existingTotalLinesAdded: Int = 0
    private var existingTotalLinesRemoved: Int = 0
    private var existingCurrentLoc: Int = 0
    private var existingFileSet: Set<String> = []
    private var existingFilesByDate: [String: Int] = [:]
    private var existingLocByDate: [String: Int] = [:]
    private var existingAuthorStats: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)] = [:]
    private var existingFileStats: [String: (commits: Int, added: Int, removed: Int)] = [:]

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

        if !forceFullRebuild,
           let last = project.lastGeneratedCommit,
           let head = repository.currentCommitHash,
           last == head,
           project.statsExists {
            print("⚡️ Stats up-to-date, skipping regeneration")
            return project.statsPath
        }

        project.isGeneratingStats = true
        try? context.save()

        defer {
            print("🏁 GitStatsEngine.generateStats() finished")
            project.isGeneratingStats = false
            project.lastGeneratedCommit = repository.currentCommitHash
            try? context.save()
        }

        // 判断是否需要增量处理
        let isIncremental = !forceFullRebuild &&
                           project.lastGeneratedCommit != nil &&
                           project.statsExists

        let sinceCommit: String? = isIncremental ? project.lastGeneratedCommit : nil

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
        // 如果是增量处理，加载现有数据
        var authorStats: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)] = [:]
        var fileStats: [String: (commits: Int, added: Int, removed: Int)] = [:]
        var fileSet = Set<String>()
        var currentLoc = 0
        var filesByDate: [String: Int] = [:]
        var locByDate: [String: Int] = [:]
        var totalCommits = 0
        var totalLinesAdded = 0
        var totalLinesRemoved = 0

        if isIncremental {
            await loadExistingStats()
            totalCommits = existingTotalCommits
            totalLinesAdded = existingTotalLinesAdded
            totalLinesRemoved = existingTotalLinesRemoved
            currentLoc = existingCurrentLoc
            fileSet = existingFileSet
            filesByDate = existingFilesByDate
            locByDate = existingLocByDate
            authorStats = existingAuthorStats
            fileStats = existingFileStats
        } else {
            await clearExistingDataOnMain()
        }
        let initDataDuration = Date().timeIntervalSince(initDataStart)

        let isoDayFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter
        }()

        var commitModels: [Commit] = []

        print("📈 Aggregating results...")
        var activeDays: Set<Date> = []
        let aggregateStart = Date()
        for (processedIndex, entry) in parsedCommits.enumerated() {
            totalCommits += 1
            let commit = entry.commit
            let day = Calendar.current.startOfDay(for: commit.authorDate)
            activeDays.insert(day)
            let dayKey = isoDayFormatter.string(from: day)

            let authorKey = "\(commit.authorName) <\(commit.authorEmail)>"
            if authorStats[authorKey] == nil {
                authorStats[authorKey] = (commit.authorName, commit.authorEmail, 0, 0, 0, commit.authorDate, commit.authorDate)
            }

            var stats = authorStats[authorKey]!
            stats.commits += 1
            stats.firstDate = stats.firstDate.map { min($0, commit.authorDate) } ?? commit.authorDate
            stats.lastDate = stats.lastDate.map { max($0, commit.authorDate) } ?? commit.authorDate
            let commitAdded = entry.numstats.reduce(0) { $0 + $1.added }
            let commitRemoved = entry.numstats.reduce(0) { $0 + $1.removed }
            stats.added += commitAdded
            stats.removed += commitRemoved
            authorStats[authorKey] = stats

            totalLinesAdded += commitAdded
            totalLinesRemoved += commitRemoved

            for numstat in entry.numstats {
                fileSet.insert(numstat.path)
                currentLoc = max(0, currentLoc + numstat.added - numstat.removed)

                var fstats = fileStats[numstat.path] ?? (0, 0, 0)
                fstats.commits += 1
                fstats.added += numstat.added
                fstats.removed += numstat.removed
                fileStats[numstat.path] = fstats
            }

            filesByDate[dayKey] = fileSet.count
            locByDate[dayKey] = currentLoc

            let commitModel = Commit(
                commitHash: commit.hash,
                authorName: commit.authorName,
                authorEmail: commit.authorEmail,
                authorDate: commit.authorDate,
                committerName: commit.committerName,
                committerEmail: commit.committerEmail,
                committerDate: commit.committerDate,
                message: commit.message,
                linesAdded: commitAdded,
                linesRemoved: commitRemoved,
                filesChanged: entry.numstats.count
            )
            commitModel.project = project
            commitModels.append(commitModel)

            if processedIndex % 50 == 0 || processedIndex + 1 == parsedCommits.count {
                progress?(ProgressUpdate(stage: .processing, processed: processedIndex + 1, total: parsedCommits.count))
                Task { @MainActor in
                    self.project.progressStage = "processing"
                    self.project.progressProcessed = processedIndex + 1
                    self.project.progressTotal = parsedCommits.count
                }
            }
        }
        let aggregateDuration = Date().timeIntervalSince(aggregateStart)

        var authorModels: [Author] = []
        for (_, stats) in authorStats {
            let author = Author(name: stats.name, email: stats.email, commitsCount: stats.commits, linesAdded: stats.added, linesRemoved: stats.removed)
            author.firstCommitDate = stats.firstDate
            author.lastCommitDate = stats.lastDate
            author.project = project
            authorModels.append(author)
        }

        var fileModels: [File] = []
        for (path, stats) in fileStats {
            let file = File(path: path, commitsCount: stats.commits, linesAdded: stats.added, linesRemoved: stats.removed)
            file.project = project
            fileModels.append(file)
        }

        let saveStart = Date()
        let commitsToInsert = commitModels
        let authorsToInsert = authorModels
        let filesToInsert = fileModels

        await insertResults(commits: commitsToInsert, authors: authorsToInsert, files: filesToInsert)
        await MainActor.run {
            project.progressStage = "done"
            project.progressProcessed = parsedCommits.count
            project.progressTotal = parsedCommits.count
        }
        let saveDuration = Date().timeIntervalSince(saveStart)

        let snapshotStart = Date()
        let snapshot: SnapshotStats?
        if let lastTreeHash = parsedCommits.last?.commit.treeHash {
            let snapshotStats = repository.calculateSnapshotStats(treeHash: lastTreeHash)
            snapshot = SnapshotStats(
                fileCount: snapshotStats.files,
                lineCount: snapshotStats.lines,
                extensions: snapshotStats.extensions
            )
        } else {
            snapshot = nil
        }
        let snapshotDuration = Date().timeIntervalSince(snapshotStart)

        // 获取所有提交用于报表生成（不再重复解析 numstat，降低处理时间）
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
            locByDate: locByDate
        )
        let reportDuration = Date().timeIntervalSince(reportStart)
        let totalDuration = Date().timeIntervalSince(totalStart)

        func fmt(_ t: TimeInterval) -> String { String(format: "%.3fs", t) }
        print("⏱ Timing => fetch: \(fmt(fetchDuration)), init: \(fmt(initDataDuration)), aggregate: \(fmt(aggregateDuration)), save: \(fmt(saveDuration)), snapshot: \(fmt(snapshotDuration)), getAll: \(fmt(allCommitsDuration)), report: \(fmt(reportDuration)), total: \(fmt(totalDuration))")

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
        locByDate: [String: Int]
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
            locByDate: locByDate
        )

        return statsPath
    }

    @MainActor
    private func clearExistingDataOnMain() {
        let targetID = project.persistentModelID
        let commitDescriptor = FetchDescriptor<Commit>(predicate: #Predicate { $0.project?.persistentModelID == targetID })
        let authorDescriptor = FetchDescriptor<Author>(predicate: #Predicate { $0.project?.persistentModelID == targetID })
        let fileDescriptor = FetchDescriptor<File>(predicate: #Predicate { $0.project?.persistentModelID == targetID })

        if let commits = try? context.fetch(commitDescriptor) {
            commits.forEach { context.delete($0) }
        }
        if let authors = try? context.fetch(authorDescriptor) {
            authors.forEach { context.delete($0) }
        }
        if let files = try? context.fetch(fileDescriptor) {
            files.forEach { context.delete($0) }
        }
    }

    @MainActor
    private func loadExistingStats() {
        let targetID = project.persistentModelID
        let commitDescriptor = FetchDescriptor<Commit>(predicate: #Predicate { $0.project?.persistentModelID == targetID })
        let authorDescriptor = FetchDescriptor<Author>(predicate: #Predicate { $0.project?.persistentModelID == targetID })
        let fileDescriptor = FetchDescriptor<File>(predicate: #Predicate { $0.project?.persistentModelID == targetID })

        // 加载作者统计
        if let authors = try? context.fetch(authorDescriptor) {
            for author in authors {
                let key = "\(author.name) <\(author.email)>"
                existingAuthorStats[key] = (
                    name: author.name,
                    email: author.email,
                    commits: author.commitsCount,
                    added: author.linesAdded,
                    removed: author.linesRemoved,
                    firstDate: author.firstCommitDate,
                    lastDate: author.lastCommitDate
                )
            }
        }

        // 加载文件统计
        if let files = try? context.fetch(fileDescriptor) {
            for file in files {
                existingFileStats[file.path] = (commits: file.commitsCount, added: file.linesAdded, removed: file.linesRemoved)
                existingFileSet.insert(file.path)
            }
        }

        // 加载提交统计
        if let commits = try? context.fetch(commitDescriptor) {
            existingTotalCommits = commits.count
            existingTotalLinesAdded = commits.reduce(0) { $0 + $1.linesAdded }
            existingTotalLinesRemoved = commits.reduce(0) { $0 + $1.linesRemoved }

            // 计算当前 LOC
            existingCurrentLoc = 0
            let isoDayFormatter: ISO8601DateFormatter = {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                return formatter
            }()

            for commit in commits.sorted(by: { $0.authorDate < $1.authorDate }) {
                existingCurrentLoc = max(0, existingCurrentLoc + commit.linesAdded - commit.linesRemoved)

                let day = Calendar.current.startOfDay(for: commit.authorDate)
                let dayKey = isoDayFormatter.string(from: day)
                existingFilesByDate[dayKey] = existingFileSet.count
                existingLocByDate[dayKey] = existingCurrentLoc
            }
        }

        print("📊 Loaded existing stats: \(existingTotalCommits) commits, \(existingTotalLinesAdded) added, \(existingTotalLinesRemoved) removed, \(existingCurrentLoc) LOC")
    }

    @MainActor
    private func insertResults(commits: [Commit], authors: [Author], files: [File]) {
        commits.forEach { context.insert($0) }
        authors.forEach { context.insert($0) }
        files.forEach { context.insert($0) }
        try? context.save()
        project.progressStage = "done"
        project.progressProcessed = commits.count
        project.progressTotal = commits.count
    }
}
