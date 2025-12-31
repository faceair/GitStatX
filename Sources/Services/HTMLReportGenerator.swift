import Foundation

struct SnapshotStats {
    let fileCount: Int
    let lineCount: Int
    let extensions: [String: (files: Int, lines: Int)]
    let totalSize: Int
}

struct TagStats {
    let name: String
    let date: Date?
    let commits: Int
    let authors: [String: Int]
    let authorCount: Int
    let daysSincePrevious: Int?
}

class HTMLReportGenerator {
    let statsPath: String

    private static let isoDayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let yearMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private static let gregorian = Calendar(identifier: .gregorian)
    private static let isoWeekCalendar = Calendar(identifier: .iso8601)

    init(statsPath: String) {
        self.statsPath = statsPath
    }

    private var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    func generateReport(
        projectName: String,
        totalCommits: Int,
        totalAuthors: Int,
        totalFiles: Int,
        totalLinesOfCode: Int,
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
    ) throws {
        guard
            let templateURL = resourceBundle.url(forResource: "report_template", withExtension: "html", subdirectory: "templates"),
            var template = try? String(contentsOf: templateURL, encoding: .utf8)
        else {
            throw ReportError.templateNotFound
        }

        let stageStart = Date()
        var lastMark = stageStart
        func mark(_ label: String) {
            let now = Date()
            let delta = now.timeIntervalSince(lastMark)
            let total = now.timeIntervalSince(stageStart)
            print(String(format: "⏱ Report %@: +%.3fs (%.3fs total)", label, delta, total))
            lastMark = now
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateStyle = .medium
        dateOnlyFormatter.timeStyle = .none
        let calendar = Self.gregorian

        let periodStart = commits.first?.authorDate
        let periodEnd = commits.last?.authorDate
        let activeDays = Set(commits.map { calendar.startOfDay(for: $0.authorDate) }).count
        let ageDays: Int
        if let start = periodStart, let end = periodEnd {
            ageDays = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0) + 1
        } else {
            ageDays = 0
        }

        let avgPerDay = ageDays > 0 ? Double(totalCommits) / Double(ageDays) : 0
        let avgPerActiveDay = activeDays > 0 ? Double(totalCommits) / Double(activeDays) : 0
        let periodRange: String
        if let start = periodStart, let end = periodEnd {
            periodRange = "\(dateOnlyFormatter.string(from: start)) - \(dateOnlyFormatter.string(from: end))"
        } else {
            periodRange = "N/A"
        }
        let activeDaysPercent = ageDays > 0 ? (Double(activeDays) / Double(ageDays) * 100) : 0
        let avgPerAuthor = totalAuthors > 0 ? Double(totalCommits) / Double(totalAuthors) : 0
        let totalSize = snapshot?.totalSize ?? 0
        let averageFileSize = totalFiles > 0 ? Double(totalSize) / Double(totalFiles) : 0

        let activityByDate = Self.calculateActivityByDate(commits: commits)
        let activityByHour = Self.calculateActivityByHour(commits: commits)
        let activityByDayOfWeek = Self.calculateActivityByDayOfWeek(commits: commits)
        let commitsByMonth = Self.calculateCommitsByMonth(commits: commits)
        let topAuthors = Self.getTopAuthors(authors: authors, limit: 10)
        let commitsByWeek = Self.calculateCommitsByWeek(commits: commits)
        let commitsByYear = Self.calculateCommitsByYear(commits: commits)
        let commitsByYearMonth = Self.calculateCommitsByYearMonth(commits: commits)
        let commitsByMonthOfYear = Self.calculateCommitsByMonthOfYear(commits: commits)
        let recentWeeks = Self.calculateRecentWeeks(commitsByWeek: commitsByWeek, limit: 32)
        let authorActiveDays = Self.calculateAuthorActiveDays(commits: commits)
        let hourOfWeek = Self.calculateHourOfWeek(commits: commits)
        let domains = Self.calculateDomains(authors: authors)
        let authorOfMonth = Self.calculateAuthorLeaders(commits: commits, component: .month)
        let authorOfYear = Self.calculateAuthorLeaders(commits: commits, component: .year)
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteFormatter.countStyle = .file
        let totalSizeLabel = byteFormatter.string(fromByteCount: Int64(totalSize))
        let averageFileSizeLabel = byteFormatter.string(fromByteCount: Int64(averageFileSize.rounded()))
        let totalTags = tags.count
        let avgCommitsPerTag = totalTags > 0 ? Double(tags.reduce(0) { $0 + $1.commits }) / Double(totalTags) : 0
        let tagGaps = tags.compactMap { $0.daysSincePrevious }
        let avgDaysBetweenTags = tagGaps.isEmpty ? 0 : Double(tagGaps.reduce(0, +)) / Double(tagGaps.count)
        mark("derived data")

        template = template.replacingOccurrences(of: "{{PROJECT_NAME}}", with: projectName)
        template = template.replacingOccurrences(of: "{{TOTAL_COMMITS}}", with: totalCommits.formatted())
        template = template.replacingOccurrences(of: "{{TOTAL_AUTHORS}}", with: totalAuthors.formatted())
        template = template.replacingOccurrences(of: "{{TOTAL_FILES}}", with: totalFiles.formatted())
        template = template.replacingOccurrences(of: "{{TOTAL_LOC}}", with: totalLinesOfCode.formatted())
        template = template.replacingOccurrences(of: "{{TOTAL_ADDED}}", with: totalLinesAdded.formatted())
        template = template.replacingOccurrences(of: "{{TOTAL_REMOVED}}", with: totalLinesRemoved.formatted())
        template = template.replacingOccurrences(of: "{{PERIOD_RANGE}}", with: periodRange)
        template = template.replacingOccurrences(of: "{{ACTIVE_DAYS}}", with: activeDays.formatted())
        template = template.replacingOccurrences(of: "{{AGE_DAYS}}", with: ageDays.formatted())
        template = template.replacingOccurrences(of: "{{AVG_PER_ACTIVE_DAY}}", with: String(format: "%.2f", avgPerActiveDay))
        template = template.replacingOccurrences(of: "{{AVG_PER_DAY}}", with: String(format: "%.2f", avgPerDay))
        template = template.replacingOccurrences(of: "{{ACTIVE_DAYS_PERCENT}}", with: String(format: "%.2f", activeDaysPercent))
        template = template.replacingOccurrences(of: "{{AVG_PER_AUTHOR}}", with: String(format: "%.2f", avgPerAuthor))
        template = template.replacingOccurrences(of: "{{TOTAL_SIZE}}", with: totalSizeLabel)
        template = template.replacingOccurrences(of: "{{AVG_FILE_SIZE}}", with: averageFileSizeLabel)
        template = template.replacingOccurrences(of: "{{TOTAL_TAGS}}", with: totalTags.formatted())
        template = template.replacingOccurrences(of: "{{AVG_COMMITS_PER_TAG}}", with: String(format: "%.2f", avgCommitsPerTag))
        template = template.replacingOccurrences(of: "{{AVG_DAYS_BETWEEN_TAGS}}", with: String(format: "%.2f", avgDaysBetweenTags))
        template = template.replacingOccurrences(of: "{{GENERATED_AT}}", with: dateFormatter.string(from: generatedAt))

        template = template.replacingOccurrences(of: "{{AUTHORS_JSON}}", with: Self.authorsToJSON(authors: authors, dateFormatter: dateFormatter))
        template = template.replacingOccurrences(of: "{{COMMITS_JSON}}", with: Self.commitsToJSON(commits: commits, dateFormatter: dateFormatter))
        template = template.replacingOccurrences(of: "{{ACTIVITY_BY_DATE_JSON}}", with: Self.dictToJSON(activityByDate))
        template = template.replacingOccurrences(of: "{{ACTIVITY_BY_HOUR_JSON}}", with: Self.arrayToJSON(activityByHour))
        template = template.replacingOccurrences(of: "{{ACTIVITY_BY_DAY_JSON}}", with: Self.arrayToJSON(activityByDayOfWeek))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_MONTH_JSON}}", with: Self.dictToJSON(commitsByMonth))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_WEEK_JSON}}", with: Self.dictToJSON(commitsByWeek))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_JSON}}", with: Self.dictToJSON(commitsByYear))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_MONTH_JSON}}", with: Self.dictToJSON(commitsByYearMonth))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_MONTH_OF_YEAR_JSON}}", with: Self.arrayToJSON((1...12).map { commitsByMonthOfYear[$0] ?? 0 }))
        template = template.replacingOccurrences(of: "{{RECENT_WEEKS_JSON}}", with: Self.recentWeeksToJSON(recentWeeks))
        template = template.replacingOccurrences(of: "{{TIMEZONE_JSON}}", with: Self.timezoneToJSON(commitsByTimezone, totalCommits: totalCommits))
        template = template.replacingOccurrences(of: "{{LINES_BY_YEAR_JSON}}", with: Self.linesByPeriodToJSON(added: linesAddedByYear, removed: linesRemovedByYear))
        template = template.replacingOccurrences(of: "{{LINES_BY_YEAR_MONTH_JSON}}", with: Self.linesByPeriodToJSON(added: linesAddedByYearMonth, removed: linesRemovedByYearMonth))
        template = template.replacingOccurrences(of: "{{FILES_JSON}}", with: Self.filesToJSON(files: files))
        template = template.replacingOccurrences(of: "{{FILES_BY_DATE_JSON}}", with: Self.dictToJSON(filesByDate))
        template = template.replacingOccurrences(of: "{{LOC_BY_DATE_JSON}}", with: Self.dictToJSON(locByDate))
        template = template.replacingOccurrences(of: "{{HOUR_OF_WEEK_JSON}}", with: Self.hourOfWeekToJSON(hourOfWeek))
        template = template.replacingOccurrences(of: "{{DOMAINS_JSON}}", with: Self.domainToJSON(domains, totalCommits: totalCommits))
        template = template.replacingOccurrences(of: "{{EXTENSION_JSON}}", with: Self.extensionToJSON(snapshot?.extensions ?? [:], totalFiles: snapshot?.fileCount ?? 0, totalLines: snapshot?.lineCount ?? 0))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_MONTH_JSON}}", with: Self.authorLeaderJSON(authorOfMonth))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_YEAR_JSON}}", with: Self.authorLeaderJSON(authorOfYear))
        template = template.replacingOccurrences(of: "{{TAGS_JSON}}", with: Self.tagsToJSON(tags: tags))
        template = template.replacingOccurrences(of: "{{TOP_AUTHORS_JSON}}", with: Self.topAuthorsToJSON(topAuthors: topAuthors))

        template = template.replacingOccurrences(of: "{{COMMIT_ROWS}}", with: Self.generateCommitRows(commits: commits, dateFormatter: dateFormatter))
        template = template.replacingOccurrences(of: "{{FILE_ROWS}}", with: Self.generateFileRows(files: files))
        template = template.replacingOccurrences(of: "{{DOMAIN_ROWS}}", with: Self.generateDomainRows(domains: domains, totalCommits: totalCommits))
        template = template.replacingOccurrences(of: "{{EXTENSION_ROWS}}", with: Self.generateExtensionRows(snapshot?.extensions ?? [:], totalFiles: snapshot?.fileCount ?? 0, totalLines: snapshot?.lineCount ?? 0))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_MONTH_ROWS}}", with: Self.generateAuthorLeaderRows(authorOfMonth))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_YEAR_ROWS}}", with: Self.generateAuthorLeaderRows(authorOfYear))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_ROWS}}", with: Self.generateCommitsByYearRows(commitsByYear: commitsByYear, linesAdded: linesAddedByYear, linesRemoved: linesRemovedByYear))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_MONTH_ROWS}}", with: Self.generateCommitsByYearMonthRows(commitsByYearMonth: commitsByYearMonth, linesAdded: linesAddedByYearMonth, linesRemoved: linesRemovedByYearMonth))
        template = template.replacingOccurrences(of: "{{AUTHOR_ROWS}}", with: Self.generateAuthorRows(authors: authors, dateFormatter: dateFormatter, totalCommits: totalCommits, activeDays: authorActiveDays))
        template = template.replacingOccurrences(of: "{{TIMEZONE_ROWS}}", with: Self.generateTimezoneRows(commitsByTimezone, totalCommits: totalCommits))
        template = template.replacingOccurrences(of: "{{TAG_ROWS}}", with: Self.generateTagRows(tags: tags))
        mark("template replacements")

        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: statsPath, withIntermediateDirectories: true)

        try template.write(toFile: URL(fileURLWithPath: statsPath).appendingPathComponent("index.html").path, atomically: true, encoding: .utf8)

        try copyChartJS()
        try copyTemplate()
        mark("write+assets")
    }

    func copyTemplate() throws {
        guard let source = resourceBundle.url(forResource: "report_template", withExtension: "html", subdirectory: "templates") else {
            throw ReportError.templateNotFound
        }

        let dest = URL(fileURLWithPath: statsPath).appendingPathComponent("report_template.html")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: source, to: dest)
    }

    func copyChartJS() throws {
        let destDir = URL(fileURLWithPath: statsPath).appendingPathComponent("Chart.js")

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

        guard let source = resourceBundle.url(forResource: "chart.min", withExtension: "js", subdirectory: "Chart.js") else {
            return
        }

        let dest = destDir.appendingPathComponent("chart.min.js")
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: source, to: dest)
    }

    private static func calculateActivityByDate(commits: [GitCommit]) -> [String: Int] {
        let calendar = gregorian
        let formatter = isoDayFormatter
        var activity: [String: Int] = [:]
        for commit in commits {
            let dateStr = formatter.string(from: calendar.startOfDay(for: commit.authorDate))
            activity[dateStr, default: 0] += 1
        }
        return activity
    }

    private static func calculateActivityByHour(commits: [GitCommit]) -> [Int] {
        var activity = Array(repeating: 0, count: 24)
        let calendar = gregorian
        for commit in commits {
            let hour = calendar.component(.hour, from: commit.authorDate)
            activity[hour] += 1
        }
        return activity
    }

    private static func calculateActivityByDayOfWeek(commits: [GitCommit]) -> [Int] {
        var activity = Array(repeating: 0, count: 7)
        let calendar = gregorian
        for commit in commits {
            let weekday = calendar.component(.weekday, from: commit.authorDate)
            activity[weekday - 1] += 1
        }
        return activity
    }

    private static func calculateCommitsByMonth(commits: [GitCommit]) -> [String: Int] {
        let formatter = yearMonthFormatter
        var commitsByMonth: [String: Int] = [:]
        for commit in commits {
            let month = formatter.string(from: commit.authorDate)
            commitsByMonth[month, default: 0] += 1
        }
        return commitsByMonth
    }

    private static func calculateCommitsByYear(commits: [GitCommit]) -> [String: Int] {
        let calendar = gregorian
        var commitsByYear: [String: Int] = [:]
        for commit in commits {
            let year = calendar.component(.year, from: commit.authorDate)
            commitsByYear["\(year)", default: 0] += 1
        }
        return commitsByYear
    }

    private static func calculateCommitsByYearMonth(commits: [GitCommit]) -> [String: Int] {
        let formatter = yearMonthFormatter
        var commitsByYearMonth: [String: Int] = [:]
        for commit in commits {
            let key = formatter.string(from: commit.authorDate)
            commitsByYearMonth[key, default: 0] += 1
        }
        return commitsByYearMonth
    }

    private static func calculateCommitsByMonthOfYear(commits: [GitCommit]) -> [Int: Int] {
        var commitsByMonthOfYear: [Int: Int] = [:]
        let calendar = gregorian
        for commit in commits {
            let month = calendar.component(.month, from: commit.authorDate)
            commitsByMonthOfYear[month, default: 0] += 1
        }
        return commitsByMonthOfYear
    }

    private static func calculateCommitsByWeek(commits: [GitCommit]) -> [String: Int] {
        let calendar = isoWeekCalendar
        var commitsByWeek: [String: Int] = [:]
        for commit in commits {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: commit.authorDate)
            let year = components.yearForWeekOfYear ?? 0
            let week = components.weekOfYear ?? 0
            let key = String(format: "%04d-W%02d", year, week)
            commitsByWeek[key, default: 0] += 1
        }
        return commitsByWeek
    }

    private static func calculateRecentWeeks(commitsByWeek: [String: Int], limit: Int) -> [(String, Int)] {
        let calendar = isoWeekCalendar
        var result: [(String, Int)] = []
        var current = Date()
        var labels: [String] = []
        for _ in 0..<limit {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: current)
            let label = String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
            labels.insert(label, at: 0)
            current = calendar.date(byAdding: .weekOfYear, value: -1, to: current) ?? current
        }
        for label in labels {
            result.append((label, commitsByWeek[label] ?? 0))
        }
        return result
    }

    private static func calculateHourOfWeek(commits: [GitCommit]) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let calendar = gregorian
        for commit in commits {
            let weekday = max(0, calendar.component(.weekday, from: commit.authorDate) - 1)
            let hour = calendar.component(.hour, from: commit.authorDate)
            grid[weekday][hour] += 1
        }
        return grid
    }

    private static func calculateDomains(authors: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)]) -> [String: Int] {
        var domains: [String: Int] = [:]
        for info in authors.values {
            guard let domain = info.email.split(separator: "@").last?.lowercased() else { continue }
            domains[domain, default: 0] += info.commits
        }
        return domains
    }

    private static func calculateAuthorLeaders(commits: [GitCommit], component: Calendar.Component) -> [String: [(name: String, commits: Int)]] {
        var result: [String: [(name: String, commits: Int)]] = [:]
        let formatter = component == .year ? yearFormatter : yearMonthFormatter

        var grouped: [String: [String: Int]] = [:]
        for commit in commits {
            let key = formatter.string(from: commit.authorDate)
            grouped[key, default: [:]][commit.authorName, default: 0] += 1
        }

        for (key, authorMap) in grouped {
            let sorted = authorMap.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
            result[key] = sorted
        }

        return result
    }

    private static func calculateAuthorActiveDays(commits: [GitCommit]) -> [String: Int] {
        var active: [String: Set<Date>] = [:]
        let calendar = gregorian
        for commit in commits {
            let key = "\(commit.authorName) <\(commit.authorEmail)>"
            let day = calendar.startOfDay(for: commit.authorDate)
            var days = active[key] ?? Set<Date>()
            days.insert(day)
            active[key] = days
        }
        return active.mapValues { $0.count }
    }

    private static func getTopAuthors(authors: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)], limit: Int) -> [(name: String, commits: Int)] {
        let authorArray = authors.values.map { ($0.name, $0.commits) }
        let sorted = authorArray.sorted { a, b in a.1 > b.1 }
        return Array(sorted.prefix(limit))
    }

    private static func topAuthorsToJSON(topAuthors: [(name: String, commits: Int)]) -> String {
        let items = topAuthors.map { "{\"name\":\(escapeJSON($0.name)),\"commits\":\($0.commits)}" }
        return "[\(items.joined(separator: ","))]"
    }

    private static func authorsToJSON(authors: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)], dateFormatter: DateFormatter) -> String {
        let items = authors.map { "{\"name\":\(escapeJSON($0.value.name)),\"email\":\(escapeJSON($0.value.email)),\"commits\":\($0.value.commits),\"added\":\($0.value.added),\"removed\":\($0.value.removed)}" }
        return "[\(items.joined(separator: ","))]"
    }

    private static func commitsToJSON(commits: [GitCommit], dateFormatter: DateFormatter) -> String {
        var result = String()
        result.reserveCapacity(max(32_768, commits.count * 96))
        result.append("[")

        var first = true
        for commit in commits.reversed() {
            if first {
                first = false
            } else {
                result.append(",")
            }
            let date = dateFormatter.string(from: commit.authorDate)
            let shortHash = String(commit.hash.prefix(7))
            result.append("{\"hash\":")
            result.append(escapeJSON(shortHash))
            result.append(",\"author\":")
            result.append(escapeJSON(commit.authorName))
            result.append(",\"date\":")
            result.append(escapeJSON(date))
            result.append(",\"message\":")
            result.append(escapeJSON(commit.message))
            result.append("}")
        }

        result.append("]")
        return result
    }

    private static func filesToJSON(files: [String: (commits: Int, added: Int, removed: Int)]) -> String {
        let sorted = files.sorted { $0.value.commits > $1.value.commits }
        let items = sorted.map { (key: String, value: (commits: Int, added: Int, removed: Int)) -> String in
            return "{\"path\":\(escapeJSON(key)),\"commits\":\(value.commits),\"added\":\(value.added),\"removed\":\(value.removed)}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    private static func dictToJSON(_ dict: [String: Int]) -> String {
        let items = dict.sorted { $0.key < $1.key }.map { (key: String, value: Int) -> String in
            return "\(escapeJSON(key)):\(value)"
        }
        return "{\(items.joined(separator: ","))}"
    }

    private static func arrayToJSON(_ arr: [Int]) -> String {
        return "[\(arr.map { String($0) }.joined(separator: ","))]"
    }

    private static func hourOfWeekToJSON(_ grid: [[Int]]) -> String {
        let rows = grid.map { row in
            "[\(row.map { String($0) }.joined(separator: ","))]"
        }
        return "[\(rows.joined(separator: ","))]"
    }

    private static func domainToJSON(_ domains: [String: Int], totalCommits: Int) -> String {
        let items = domains.sorted { $0.value > $1.value }.map { key, value in
            let percent = totalCommits > 0 ? (Double(value) / Double(totalCommits) * 100) : 0
            return "{\"domain\":\(escapeJSON(key)),\"commits\":\(value),\"percent\":\(String(format: "%.2f", percent))}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    private static func extensionToJSON(_ extensions: [String: (files: Int, lines: Int)], totalFiles: Int, totalLines: Int) -> String {
        let items = extensions.sorted { $0.value.files > $1.value.files }.map { key, value in
            let filePercent = totalFiles > 0 ? (Double(value.files) / Double(totalFiles) * 100) : 0
            let linePercent = totalLines > 0 ? (Double(value.lines) / Double(totalLines) * 100) : 0
            let filePercentStr = String(format: "%.2f", filePercent)
            let linePercentStr = String(format: "%.2f", linePercent)
            return "{\"ext\":\(escapeJSON(key)),\"files\":\(value.files),\"lines\":\(value.lines),\"filePercent\":\(filePercentStr),\"linePercent\":\(linePercentStr)}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    private static func linesByPeriodToJSON(added: [String: Int], removed: [String: Int]) -> String {
        let keys = Set(added.keys).union(removed.keys).sorted()
        let items = keys.map { key -> String in
            let add = added[key] ?? 0
            let rem = removed[key] ?? 0
            let net = add - rem
            return "{\"period\":\(escapeJSON(key)),\"added\":\(add),\"removed\":\(rem),\"net\":\(net)}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    private static func recentWeeksToJSON(_ weeks: [(String, Int)]) -> String {
        let items = weeks.map { "{\"label\":\(escapeJSON($0.0)),\"commits\":\($0.1)}" }
        return "[\(items.joined(separator: ","))]"
    }

    private static func timezoneToJSON(_ timezones: [Int: Int], totalCommits: Int) -> String {
        let sorted = timezones.keys.sorted()
        let items = sorted.map { offset -> String in
            let commits = timezones[offset] ?? 0
            let percent = totalCommits > 0 ? (Double(commits) / Double(totalCommits) * 100) : 0
            return "{\"offset\":\(escapeJSON(formatTimezoneOffset(offset))),\"commits\":\(commits),\"percent\":\(String(format: "%.2f", percent))}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    private static func tagsToJSON(tags: [TagStats]) -> String {
        let formatter = ISO8601DateFormatter()
        let sorted = tags.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let items = sorted.map { tag -> String in
            let date = tag.date.map { escapeJSON(formatter.string(from: $0)) } ?? "\"\""
            let authors = tag.authors.sorted { $0.value > $1.value }.map { "{\"name\":\(escapeJSON($0.key)),\"commits\":\($0.value)}" }.joined(separator: ",")
            let gap = tag.daysSincePrevious.map(String.init) ?? "null"
            return "{\"name\":\(escapeJSON(tag.name)),\"date\":\(date),\"commits\":\(tag.commits),\"authorCount\":\(tag.authorCount),\"daysSincePrevious\":\(gap),\"authors\":[\(authors)]}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    private static func authorLeaderJSON(_ leaders: [String: [(name: String, commits: Int)]]) -> String {
        let items = leaders.sorted { $0.key < $1.key }.map { key, list in
            let leadersJSON = list.map { "{\"name\":\(escapeJSON($0.name)),\"commits\":\($0.commits)}" }.joined(separator: ",")
            return "{\"period\":\(escapeJSON(key)),\"leaders\":[\(leadersJSON)]}"
        }
        return "[\(items.joined(separator: ","))]"
    }

    private static func escapeJSON(_ str: String) -> String {
        let escaped = str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func formatTimezoneOffset(_ minutes: Int) -> String {
        let sign = minutes >= 0 ? "+" : "-"
        let value = abs(minutes)
        let hours = value / 60
        let mins = value % 60
        return String(format: "UTC%@%02d:%02d", sign, hours, mins)
    }

    private static func generateDomainRows(domains: [String: Int], totalCommits: Int) -> String {
        let sorted = domains.sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
        return sorted.map { domain, commits in
            let percent = totalCommits > 0 ? (Double(commits) / Double(totalCommits) * 100) : 0
            return """
            <tr>
                <td>\(escapeHTML(domain))</td>
                <td>\(commits.formatted())</td>
                <td>\(String(format: "%.2f", percent))%</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateExtensionRows(_ extensions: [String: (files: Int, lines: Int)], totalFiles: Int, totalLines: Int) -> String {
        let sorted = extensions.sorted { lhs, rhs in lhs.value.files == rhs.value.files ? lhs.key < rhs.key : lhs.value.files > rhs.value.files }
        return sorted.map { ext, stats in
            let filePercent = totalFiles > 0 ? (Double(stats.files) / Double(totalFiles) * 100) : 0
            let linePercent = totalLines > 0 ? (Double(stats.lines) / Double(totalLines) * 100) : 0
            let linesPerFile = stats.files > 0 ? Double(stats.lines) / Double(stats.files) : 0
            let label = ext == "no-extension" ? "No Extension" : ext
            return """
            <tr>
                <td>\(escapeHTML(label))</td>
                <td>\(stats.files.formatted())</td>
                <td>\(String(format: "%.2f", filePercent))%</td>
                <td>\(stats.lines.formatted())</td>
                <td>\(String(format: "%.2f", linePercent))%</td>
                <td>\(String(format: "%.2f", linesPerFile))</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateAuthorLeaderRows(_ leaders: [String: [(name: String, commits: Int)]]) -> String {
        let sortedPeriods = leaders.keys.sorted()
        return sortedPeriods.compactMap { period in
            guard let entries = leaders[period], let top = entries.first else { return nil }
            let next = entries.dropFirst().prefix(5).map { "\($0.name) (\($0.commits))" }.joined(separator: ", ")
            return """
            <tr>
                <td>\(escapeHTML(period))</td>
                <td>\(escapeHTML(top.name))</td>
                <td>\(top.commits.formatted())</td>
                <td>\(escapeHTML(next))</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateCommitsByYearRows(commitsByYear: [String: Int], linesAdded: [String: Int], linesRemoved: [String: Int]) -> String {
        let keys = Set(commitsByYear.keys).union(linesAdded.keys).union(linesRemoved.keys)
        let sorted = keys.sorted { $0 > $1 }
        return sorted.map { year in
            let count = commitsByYear[year] ?? 0
            let added = linesAdded[year] ?? 0
            let removed = linesRemoved[year] ?? 0
            let net = added - removed
            return """
            <tr>
                <td>\(escapeHTML(year))</td>
                <td>\(count.formatted())</td>
                <td>\(added.formatted())</td>
                <td>\(removed.formatted())</td>
                <td>\(net.formatted())</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateCommitsByYearMonthRows(commitsByYearMonth: [String: Int], linesAdded: [String: Int], linesRemoved: [String: Int]) -> String {
        let keys = Set(commitsByYearMonth.keys).union(linesAdded.keys).union(linesRemoved.keys)
        let sorted = keys.sorted { $0 > $1 }
        return sorted.map { ym in
            let count = commitsByYearMonth[ym] ?? 0
            let added = linesAdded[ym] ?? 0
            let removed = linesRemoved[ym] ?? 0
            let net = added - removed
            return """
            <tr>
                <td>\(escapeHTML(ym))</td>
                <td>\(count.formatted())</td>
                <td>\(added.formatted())</td>
                <td>\(removed.formatted())</td>
                <td>\(net.formatted())</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateAuthorRows(authors: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)], dateFormatter: DateFormatter, totalCommits: Int, activeDays: [String: Int]) -> String {
        let calendar = Calendar.current
        let sorted = authors.sorted { lhs, rhs in lhs.value.commits == rhs.value.commits ? lhs.value.name < rhs.value.name : lhs.value.commits > rhs.value.commits }
        return sorted.enumerated().map { index, entry -> String in
            let author = entry.value
            let key = entry.key
            let firstDate = author.firstDate.map { dateFormatter.string(from: $0) } ?? "N/A"
            let lastDate = author.lastDate.map { dateFormatter.string(from: $0) } ?? "N/A"
            let ageDays: Int
            if let first = author.firstDate, let last = author.lastDate {
                ageDays = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)).day ?? 0) + 1
            } else {
                ageDays = 0
            }
            let percent = totalCommits > 0 ? (Double(author.commits) / Double(totalCommits) * 100) : 0
            let active = activeDays[key] ?? 0
            let rank = index + 1
            return """
            <tr>
                <td>\(escapeHTML(author.name))</td>
                <td><code>\(escapeHTML(author.email))</code></td>
                <td>\(author.commits.formatted())</td>
                <td>\(String(format: "%.2f", percent))%</td>
                <td>\(author.added.formatted())</td>
                <td>\(author.removed.formatted())</td>
                <td>\(firstDate)</td>
                <td>\(lastDate)</td>
                <td>\(ageDays.formatted())</td>
                <td>\(active.formatted())</td>
                <td>\(rank)</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateCommitRows(commits: [GitCommit], dateFormatter: DateFormatter) -> String {
        var builder = String()
        builder.reserveCapacity(max(32_768, commits.count * 96))

        for commit in commits.reversed() {
            let date = dateFormatter.string(from: commit.authorDate)
            let shortHash = String(commit.hash.prefix(7))
            builder.append(
                """
                <tr>
                    <td><code>\(shortHash)</code></td>
                    <td>\(escapeHTML(commit.authorName))</td>
                    <td>\(date)</td>
                    <td>\(escapeHTML(commit.message))</td>
                </tr>
                """
            )
            builder.append("\n")
        }

        return builder
    }

    private static func generateFileRows(files: [String: (commits: Int, added: Int, removed: Int)]) -> String {
        let sorted = files.sorted { $0.value.commits > $1.value.commits }
        return sorted.map { (path, stats) -> String in
            return """
            <tr>
                <td><code>\(escapeHTML(path))</code></td>
                <td>\(stats.commits.formatted())</td>
                <td>\(stats.added.formatted())</td>
                <td>\(stats.removed.formatted())</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateTimezoneRows(_ timezones: [Int: Int], totalCommits: Int) -> String {
        let sorted = timezones.keys.sorted()
        return sorted.map { offset -> String in
            let commits = timezones[offset] ?? 0
            let percent = totalCommits > 0 ? (Double(commits) / Double(totalCommits) * 100) : 0
            return """
            <tr>
                <td>\(escapeHTML(formatTimezoneOffset(offset)))</td>
                <td>\(commits.formatted())</td>
                <td>\(String(format: "%.2f", percent))%</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateTagRows(tags: [TagStats]) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let sorted = tags.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return sorted.map { tag in
            let date = tag.date.map { formatter.string(from: $0) } ?? "N/A"
            let authors = tag.authors.sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
                .map { "\(escapeHTML($0.key)) (\($0.value))" }
                .joined(separator: ", ")
            let daysSincePrevious = tag.daysSincePrevious.map(String.init) ?? "N/A"
            return """
            <tr>
                <td>\(escapeHTML(tag.name))</td>
                <td>\(date)</td>
                <td>\(tag.commits.formatted())</td>
                <td>\(escapeHTML(authors))</td>
                <td>\(tag.authorCount.formatted())</td>
                <td>\(daysSincePrevious)</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum ReportError: Error, LocalizedError {
    case templateNotFound

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "HTML template file not found"
        }
    }
}
