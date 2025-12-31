import XCTest
import SwiftData
@testable import GitStatX

final class PerfTraceRealRepoTests: XCTestCase {
    func testPerfTraceC2GoAsm() async throws {
        let repoPath = "/Users/faceair/Developer/c2goasm"
        guard FileManager.default.fileExists(atPath: repoPath) else {
            throw XCTSkip("Repo not found at \(repoPath)")
        }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStatXPerfTrace_\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: Project.self,
            Author.self,
            Commit.self,
            File.self,
            configurations: config
        )
        let context = ModelContext(container)
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let project = Project(name: "Perf c2goasm", path: repoPath)
        context.insert(project)

        let engine = GitStatsEngine(project: project, context: context)

        let start = Date()
        try await engine.generateStats(forceFullRebuild: true)
        let total = Date().timeIntervalSince(start)
        print(String(format: "⏱ PerfTrace c2goasm total: %.3fs", total))
    }

    func testPerfTraceGuanceDB() async throws {
        let repoPath = "/Users/faceair/Developer/GuanceDB"
        guard FileManager.default.fileExists(atPath: repoPath) else {
            throw XCTSkip("Repo not found at \(repoPath)")
        }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStatXPerfTrace_\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: Project.self,
            Author.self,
            Commit.self,
            File.self,
            configurations: config
        )
        let context = ModelContext(container)
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let project = Project(name: "Perf GuanceDB", path: repoPath)
        context.insert(project)

        let engine = GitStatsEngine(project: project, context: context)

        let start = Date()
        try await engine.generateStats(forceFullRebuild: true)
        let total = Date().timeIntervalSince(start)
        print(String(format: "⏱ PerfTrace GuanceDB total: %.3fs", total))
    }
}
