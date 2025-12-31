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
            configurations: config
        )
        let context = ModelContext(container)

        let project = Project(name: "Smoke", path: "/tmp")
        context.insert(project)
        try context.save()

        try? FileManager.default.removeItem(at: storeURL)
    }

    func testCanUpdateProjectMetadata() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStatXSmokeUpdate_\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: Project.self,
            configurations: config
        )
        let context = ModelContext(container)

        let project = Project(name: "SmokeFull", path: "/tmp/repo")
        context.insert(project)
        try context.save()

        project.lastGeneratedCommit = "abc123"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(fetched.first?.lastGeneratedCommit, "abc123")
        try? FileManager.default.removeItem(at: storeURL)
    }
}
