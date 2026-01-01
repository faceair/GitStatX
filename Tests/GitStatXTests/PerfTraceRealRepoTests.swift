import XCTest
import SwiftData
@testable import GitStatX

final class PerfTraceRealRepoTests: XCTestCase {
    func testPerfTraceVictoriaMetrics() async throws {
        let repoPath = "/Users/faceair/Developer/VictoriaMetrics"
        guard FileManager.default.fileExists(atPath: repoPath) else {
            throw XCTSkip("Repo not found at \(repoPath)")
        }

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            configurations: config
        )
        let context = ModelContext(container)

        let project = Project(name: "Perf VictoriaMetrics", path: repoPath)
        context.insert(project)

        let engine = GitStatsEngine(project: project, context: context)

        let start = Date()
        _ = try await engine.generateStats(forceFullRebuild: true)
        let total = Date().timeIntervalSince(start)
        print(String(format: "⏱ PerfTrace VictoriaMetrics total: %.3fs", total))
    }
}
