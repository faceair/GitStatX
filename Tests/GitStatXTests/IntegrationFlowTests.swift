import XCTest
import SwiftData
@testable import GitStatX

final class IntegrationFlowTests: XCTestCase {
    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed")
    }

    private func makeTempRepo() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let repoDir = tempDir.appendingPathComponent("GitStatXIntegration_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try runGit(["init"], in: repoDir)
        try runGit(["config", "user.name", "Test User"], in: repoDir)
        try runGit(["config", "user.email", "test@example.com"], in: repoDir)
        try runGit(["config", "commit.gpgsign", "false"], in: repoDir)
        return repoDir
    }

    @MainActor
    func testFullGenerateStatsFlow() async throws {
        let repoDir = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: repoDir) }

        let fileURL = repoDir.appendingPathComponent("test.txt")
        try "Line 1\nLine 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "test.txt"], in: repoDir)
        try runGit(["commit", "-m", "Initial commit"], in: repoDir)

        try "Line 1\nLine 2\nLine 3\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "test.txt"], in: repoDir)
        try runGit(["commit", "-m", "Second commit"], in: repoDir)

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStatXIntegrationStore_\(UUID().uuidString)")
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

        let project = Project(name: "Integration Test", path: repoDir.path)
        context.insert(project)

        let engine = GitStatsEngine(project: project, context: context)
        try await engine.generateStats()

        let commits = try context.fetch(FetchDescriptor<Commit>())
        XCTAssertEqual(commits.count, 2, "Should record two commits")

        let authors = try context.fetch(FetchDescriptor<Author>())
        XCTAssertEqual(authors.count, 1, "Should aggregate to one author")
        XCTAssertEqual(authors.first?.commitsCount, 2, "Author commit count should match")

        let files = try context.fetch(FetchDescriptor<File>())
        XCTAssertEqual(files.count, 1, "Should track one file")

        XCTAssertTrue(FileManager.default.fileExists(atPath: project.statsIndexPath), "Report index.html should be generated")

        try? FileManager.default.removeItem(atPath: project.statsPath)
    }
}
