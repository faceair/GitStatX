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
}
