import XCTest
import SwiftData
@testable import GitStatX

final class SwiftDataSmokeTests: XCTestCase {
    func testCanSaveMinimalProject() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStatXSmoke_\(UUID().uuidString)")
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

        let project = Project(name: "Smoke", path: "/tmp")
        context.insert(project)
        try context.save()

        try? FileManager.default.removeItem(at: storeURL)
    }

    func testCanSaveFullEntities() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStatXSmokeFull_\(UUID().uuidString)")
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

        let project = Project(name: "SmokeFull", path: "/tmp/repo")
        context.insert(project)

        print("🔹 Saving project")
        try context.save() // save project

        let author = Author(name: "Test User", email: "test@example.com", commitsCount: 2, linesAdded: 4, linesRemoved: 1)
        author.project = project
        context.insert(author)
        print("🔹 Saving author")
        try context.save() // save author

        let commit = Commit(
            commitHash: String(repeating: "a", count: 40),
            authorName: "Test User",
            authorEmail: "test@example.com",
            authorDate: Date(),
            committerName: "Test User",
            committerEmail: "test@example.com",
            committerDate: Date(),
            message: "msg",
            linesAdded: 4,
            linesRemoved: 1,
            filesChanged: 1
        )
        commit.project = project
        context.insert(commit)
        print("🔹 Saving commit")
        try context.save() // save commit

        let file = File(path: "test.txt", commitsCount: 2, linesAdded: 4, linesRemoved: 1)
        file.project = project
        context.insert(file)
        print("🔹 Saving file")
        try context.save() // save file
        try? FileManager.default.removeItem(at: storeURL)
    }
}
