import Foundation

struct SnapshotStats {
    let fileCount: Int
    let lineCount: Int
    let extensions: [String: (files: Int, lines: Int)]
}

class HTMLReportGenerator {
    let statsPath: String

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
        locByDate: [String: Int]
    ) throws {
        guard
            let templateURL = resourceBundle.url(forResource: "report_template", withExtension: "html", subdirectory: "templates"),
            var template = try? String(contentsOf: templateURL, encoding: .utf8)
        else {
            throw ReportError.templateNotFound
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateStyle = .medium
        dateOnlyFormatter.timeStyle = .none
        let calendar = Calendar.current

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

        let activityByDate = Self.calculateActivityByDate(commits: commits)
        let activityByHour = Self.calculateActivityByHour(commits: commits)
        let activityByDayOfWeek = Self.calculateActivityByDayOfWeek(commits: commits)
        let commitsByMonth = Self.calculateCommitsByMonth(commits: commits)
        let topAuthors = Self.getTopAuthors(authors: authors, limit: 10)
        let commitsByWeek = Self.calculateCommitsByWeek(commits: commits)
        let commitsByYear = Self.calculateCommitsByYear(commits: commits)
        let commitsByYearMonth = Self.calculateCommitsByYearMonth(commits: commits)
        let hourOfWeek = Self.calculateHourOfWeek(commits: commits)
        let domains = Self.calculateDomains(authors: authors)
        let authorOfMonth = Self.calculateAuthorLeaders(commits: commits, component: .month)
        let authorOfYear = Self.calculateAuthorLeaders(commits: commits, component: .year)

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

        template = template.replacingOccurrences(of: "{{AUTHORS_JSON}}", with: Self.authorsToJSON(authors: authors, dateFormatter: dateFormatter))
        template = template.replacingOccurrences(of: "{{COMMITS_JSON}}", with: Self.commitsToJSON(commits: commits, dateFormatter: dateFormatter))
        template = template.replacingOccurrences(of: "{{ACTIVITY_BY_DATE_JSON}}", with: Self.dictToJSON(activityByDate))
        template = template.replacingOccurrences(of: "{{ACTIVITY_BY_HOUR_JSON}}", with: Self.arrayToJSON(activityByHour))
        template = template.replacingOccurrences(of: "{{ACTIVITY_BY_DAY_JSON}}", with: Self.arrayToJSON(activityByDayOfWeek))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_MONTH_JSON}}", with: Self.dictToJSON(commitsByMonth))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_WEEK_JSON}}", with: Self.dictToJSON(commitsByWeek))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_JSON}}", with: Self.dictToJSON(commitsByYear))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_MONTH_JSON}}", with: Self.dictToJSON(commitsByYearMonth))
        template = template.replacingOccurrences(of: "{{FILES_JSON}}", with: Self.filesToJSON(files: files))
        template = template.replacingOccurrences(of: "{{FILES_BY_DATE_JSON}}", with: Self.dictToJSON(filesByDate))
        template = template.replacingOccurrences(of: "{{LOC_BY_DATE_JSON}}", with: Self.dictToJSON(locByDate))
        template = template.replacingOccurrences(of: "{{HOUR_OF_WEEK_JSON}}", with: Self.hourOfWeekToJSON(hourOfWeek))
        template = template.replacingOccurrences(of: "{{DOMAINS_JSON}}", with: Self.domainToJSON(domains, totalCommits: totalCommits))
        template = template.replacingOccurrences(of: "{{EXTENSION_JSON}}", with: Self.extensionToJSON(snapshot?.extensions ?? [:], totalFiles: snapshot?.fileCount ?? 0, totalLines: snapshot?.lineCount ?? 0))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_MONTH_JSON}}", with: Self.authorLeaderJSON(authorOfMonth))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_YEAR_JSON}}", with: Self.authorLeaderJSON(authorOfYear))
        template = template.replacingOccurrences(of: "{{TOP_AUTHORS_JSON}}", with: Self.topAuthorsToJSON(topAuthors: topAuthors))

        template = template.replacingOccurrences(of: "{{AUTHOR_ROWS}}", with: Self.generateAuthorRows(authors: authors, dateFormatter: dateFormatter))
        template = template.replacingOccurrences(of: "{{COMMIT_ROWS}}", with: Self.generateCommitRows(commits: commits, dateFormatter: dateFormatter))
        template = template.replacingOccurrences(of: "{{FILE_ROWS}}", with: Self.generateFileRows(files: files))
        template = template.replacingOccurrences(of: "{{DOMAIN_ROWS}}", with: Self.generateDomainRows(domains: domains, totalCommits: totalCommits))
        template = template.replacingOccurrences(of: "{{EXTENSION_ROWS}}", with: Self.generateExtensionRows(snapshot?.extensions ?? [:], totalFiles: snapshot?.fileCount ?? 0, totalLines: snapshot?.lineCount ?? 0))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_MONTH_ROWS}}", with: Self.generateAuthorLeaderRows(authorOfMonth))
        template = template.replacingOccurrences(of: "{{AUTHOR_OF_YEAR_ROWS}}", with: Self.generateAuthorLeaderRows(authorOfYear))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_ROWS}}", with: Self.generateCommitsByYearRows(commitsByYear: commitsByYear))
        template = template.replacingOccurrences(of: "{{COMMITS_BY_YEAR_MONTH_ROWS}}", with: Self.generateCommitsByYearMonthRows(commitsByYearMonth: commitsByYearMonth))

        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: statsPath, withIntermediateDirectories: true)

        try template.write(toFile: URL(fileURLWithPath: statsPath).appendingPathComponent("index.html").path, atomically: true, encoding: .utf8)

        try copyChartJS()
        try copyTemplate()
    }

    func copyTemplate() throws {
        guard let source = resourceBundle.url(forResource: "report_template", withExtension: "html", subdirectory: "templates") else {
            throw ReportError.templateNotFound
        }

        let dest = URL(fileURLWithPath: statsPath).appendingPathComponent("report_template.html")
        try FileManager.default.copyItem(at: source, to: dest)
    }

    func copyChartJS() throws {
        let destDir = URL(fileURLWithPath: statsPath).appendingPathComponent("Chart.js")

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

        guard let source = resourceBundle.url(forResource: "chart.min", withExtension: "js", subdirectory: "Chart.js") else {
            return
        }

        let dest = destDir.appendingPathComponent("chart.min.js")
        try fileManager.copyItem(at: source, to: dest)
    }

    private static func calculateActivityByDate(commits: [GitCommit]) -> [String: Int] {
        let calendar = Calendar.current
        var activity: [String: Int] = [:]
        for commit in commits {
            let dateStr = ISO8601DateFormatter().string(from: calendar.startOfDay(for: commit.authorDate))
            activity[dateStr, default: 0] += 1
        }
        return activity
    }

    private static func calculateActivityByHour(commits: [GitCommit]) -> [Int] {
        var activity = Array(repeating: 0, count: 24)
        for commit in commits {
            let hour = Calendar.current.component(.hour, from: commit.authorDate)
            activity[hour] += 1
        }
        return activity
    }

    private static func calculateActivityByDayOfWeek(commits: [GitCommit]) -> [Int] {
        var activity = Array(repeating: 0, count: 7)
        for commit in commits {
            let weekday = Calendar.current.component(.weekday, from: commit.authorDate)
            activity[weekday - 1] += 1
        }
        return activity
    }

    private static func calculateCommitsByMonth(commits: [GitCommit]) -> [String: Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        var commitsByMonth: [String: Int] = [:]
        for commit in commits {
            let month = formatter.string(from: commit.authorDate)
            commitsByMonth[month, default: 0] += 1
        }
        return commitsByMonth
    }

    private static func calculateCommitsByYear(commits: [GitCommit]) -> [String: Int] {
        let calendar = Calendar.current
        var commitsByYear: [String: Int] = [:]
        for commit in commits {
            let year = calendar.component(.year, from: commit.authorDate)
            commitsByYear["\(year)", default: 0] += 1
        }
        return commitsByYear
    }

    private static func calculateCommitsByYearMonth(commits: [GitCommit]) -> [String: Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        var commitsByYearMonth: [String: Int] = [:]
        for commit in commits {
            let key = formatter.string(from: commit.authorDate)
            commitsByYearMonth[key, default: 0] += 1
        }
        return commitsByYearMonth
    }

    private static func calculateCommitsByWeek(commits: [GitCommit]) -> [String: Int] {
        let calendar = Calendar(identifier: .iso8601)
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

    private static func calculateHourOfWeek(commits: [GitCommit]) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let calendar = Calendar.current
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
        let formatter = DateFormatter()
        formatter.dateFormat = component == .year ? "yyyy" : "yyyy-MM"

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
        let items = commits.reversed().map { commit -> String in
            let date = dateFormatter.string(from: commit.authorDate)
            let message = commit.message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"hash\":\(escapeJSON(String(commit.hash.prefix(7)))),\"author\":\(escapeJSON(commit.authorName)),\"date\":\(escapeJSON(date)),\"message\":\(escapeJSON(message))}"
        }
        return "[\(items.joined(separator: ","))]"
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
            let label = ext == "no-extension" ? "No Extension" : ext
            return """
            <tr>
                <td>\(escapeHTML(label))</td>
                <td>\(stats.files.formatted())</td>
                <td>\(String(format: "%.2f", filePercent))%</td>
                <td>\(stats.lines.formatted())</td>
                <td>\(String(format: "%.2f", linePercent))%</td>
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

    private static func generateCommitsByYearRows(commitsByYear: [String: Int]) -> String {
        let sorted = commitsByYear.sorted { lhs, rhs in lhs.key > rhs.key }
        return sorted.map { year, count in
            """
            <tr>
                <td>\(escapeHTML(year))</td>
                <td>\(count.formatted())</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateCommitsByYearMonthRows(commitsByYearMonth: [String: Int]) -> String {
        let sorted = commitsByYearMonth.sorted { lhs, rhs in lhs.key > rhs.key }
        return sorted.map { ym, count in
            """
            <tr>
                <td>\(escapeHTML(ym))</td>
                <td>\(count.formatted())</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateAuthorRows(authors: [String: (name: String, email: String, commits: Int, added: Int, removed: Int, firstDate: Date?, lastDate: Date?)], dateFormatter: DateFormatter) -> String {
        let sorted = authors.values.sorted { a, b in a.commits > b.commits }
        return sorted.map { author -> String in
            let firstDate = author.firstDate.map { dateFormatter.string(from: $0) } ?? "N/A"
            let lastDate = author.lastDate.map { dateFormatter.string(from: $0) } ?? "N/A"
            return """
            <tr>
                <td>\(escapeHTML(author.name))</td>
                <td><code>\(escapeHTML(author.email))</code></td>
                <td>\(author.commits.formatted())</td>
                <td>\(author.added.formatted())</td>
                <td>\(author.removed.formatted())</td>
                <td>\(firstDate)</td>
                <td>\(lastDate)</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateCommitRows(commits: [GitCommit], dateFormatter: DateFormatter) -> String {
        return commits.reversed().map { commit -> String in
            let date = dateFormatter.string(from: commit.authorDate)
            let shortHash = String(commit.hash.prefix(7))
            return """
            <tr>
                <td><code>\(shortHash)</code></td>
                <td>\(escapeHTML(commit.authorName))</td>
                <td>\(date)</td>
                <td>\(escapeHTML(commit.message))</td>
            </tr>
            """
        }.joined(separator: "\n")
    }

    private static func generateFileRows(files: [String: (commits: Int, added: Int, removed: Int)]) -> String {
        let sorted = files.sorted { $0.value.commits > $1.value.commits }
        return sorted.map { (path, stats) -> String in
            let netClass = (stats.added - stats.removed) >= 0 ? "badge-success" : "badge-warning"
            let netSign = (stats.added - stats.removed) >= 0 ? "+" : ""
            let netValue = (stats.added - stats.removed).formatted()
            return """
            <tr>
                <td><code>\(escapeHTML(path))</code></td>
                <td>\(stats.commits.formatted())</td>
                <td>\(stats.added.formatted())</td>
                <td><span class="badge \(netClass)">\(netSign)\(netValue)</span></td>
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
