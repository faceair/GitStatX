import Foundation

struct StatsCache: Codable {
    struct Author: Codable {
        let name: String
        let email: String
        let commits: Int
        let added: Int
        let removed: Int
        let firstDate: Date?
        let lastDate: Date?
    }

    struct File: Codable {
        let commits: Int
        let added: Int
        let removed: Int
    }

    let lastCommit: String?
    let totalCommits: Int
    let totalLinesAdded: Int
    let totalLinesRemoved: Int
    let currentLoc: Int
    let fileSet: [String]
    let filesByDate: [String: Int]
    let locByDate: [String: Int]
    let authorStats: [String: Author]
    let fileStats: [String: File]

    let linesAddedByYear: [String: Int]
    let linesRemovedByYear: [String: Int]
    let linesAddedByYearMonth: [String: Int]
    let linesRemovedByYearMonth: [String: Int]
    let hasLineBreakdown: Bool

    private enum CodingKeys: String, CodingKey {
        case lastCommit
        case totalCommits
        case totalLinesAdded
        case totalLinesRemoved
        case currentLoc
        case fileSet
        case filesByDate
        case locByDate
        case authorStats
        case fileStats
        case linesAddedByYear
        case linesRemovedByYear
        case linesAddedByYearMonth
        case linesRemovedByYearMonth
        case hasLineBreakdown
    }

    init(
        lastCommit: String?,
        totalCommits: Int,
        totalLinesAdded: Int,
        totalLinesRemoved: Int,
        currentLoc: Int,
        fileSet: [String],
        filesByDate: [String: Int],
        locByDate: [String: Int],
        authorStats: [String: Author],
        fileStats: [String: File],
        linesAddedByYear: [String: Int],
        linesRemovedByYear: [String: Int],
        linesAddedByYearMonth: [String: Int],
        linesRemovedByYearMonth: [String: Int],
        hasLineBreakdown: Bool
    ) {
        self.lastCommit = lastCommit
        self.totalCommits = totalCommits
        self.totalLinesAdded = totalLinesAdded
        self.totalLinesRemoved = totalLinesRemoved
        self.currentLoc = currentLoc
        self.fileSet = fileSet
        self.filesByDate = filesByDate
        self.locByDate = locByDate
        self.authorStats = authorStats
        self.fileStats = fileStats
        self.linesAddedByYear = linesAddedByYear
        self.linesRemovedByYear = linesRemovedByYear
        self.linesAddedByYearMonth = linesAddedByYearMonth
        self.linesRemovedByYearMonth = linesRemovedByYearMonth
        self.hasLineBreakdown = hasLineBreakdown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastCommit = try container.decodeIfPresent(String.self, forKey: .lastCommit)
        totalCommits = try container.decode(Int.self, forKey: .totalCommits)
        totalLinesAdded = try container.decode(Int.self, forKey: .totalLinesAdded)
        totalLinesRemoved = try container.decode(Int.self, forKey: .totalLinesRemoved)
        currentLoc = try container.decode(Int.self, forKey: .currentLoc)
        fileSet = try container.decode([String].self, forKey: .fileSet)
        filesByDate = try container.decode([String: Int].self, forKey: .filesByDate)
        locByDate = try container.decode([String: Int].self, forKey: .locByDate)
        authorStats = try container.decode([String: Author].self, forKey: .authorStats)
        fileStats = try container.decode([String: File].self, forKey: .fileStats)
        linesAddedByYear = try container.decodeIfPresent([String: Int].self, forKey: .linesAddedByYear) ?? [:]
        linesRemovedByYear = try container.decodeIfPresent([String: Int].self, forKey: .linesRemovedByYear) ?? [:]
        linesAddedByYearMonth = try container.decodeIfPresent([String: Int].self, forKey: .linesAddedByYearMonth) ?? [:]
        linesRemovedByYearMonth = try container.decodeIfPresent([String: Int].self, forKey: .linesRemovedByYearMonth) ?? [:]
        hasLineBreakdown = try container.decodeIfPresent(Bool.self, forKey: .hasLineBreakdown) ?? false
    }
}
