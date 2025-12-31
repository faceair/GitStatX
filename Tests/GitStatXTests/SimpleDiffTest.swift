import XCTest
@testable import GitStatX

final class SimpleDiffTest: XCTestCase {
    var testRepository: GitRepository!
    var testRepositoryPath: String!

    override func setUpWithError() throws {
        print("\n🧪 Setting up simple diff test...")

        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GitStatXSimpleTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        print("📁 Created test directory: \(testDir.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = testDir

        try process.run()
        process.waitUntilExit()

        let configProcess = Process()
        configProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        configProcess.arguments = ["config", "user.name", "Test User"]
        configProcess.currentDirectoryURL = testDir
        try configProcess.run()
        configProcess.waitUntilExit()

        let emailProcess = Process()
        emailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        emailProcess.arguments = ["config", "user.email", "test@example.com"]
        emailProcess.currentDirectoryURL = testDir
        try emailProcess.run()
        emailProcess.waitUntilExit()

        let gpgsignProcess = Process()
        gpgsignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gpgsignProcess.arguments = ["config", "commit.gpgsign", "false"]
        gpgsignProcess.currentDirectoryURL = testDir
        try gpgsignProcess.run()
        gpgsignProcess.waitUntilExit()

        testRepositoryPath = testDir.path
        testRepository = GitRepository(path: testRepositoryPath)

        print("✅ Setup complete")
    }

    override func tearDownWithError() throws {
        if let path = testRepositoryPath {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    func testSimpleDiff() throws {
        print("\n🧪 Testing simple diff...")

        print("📝 Creating initial file...")
        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Line 1".write(to: testFile, atomically: true, encoding: .utf8)
        print("✅ Initial file created")

        print("📝 Adding file to git...")
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()
        print("✅ File added to git")

        print("📝 Creating first commit...")
        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Initial commit"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()
        print("✅ First commit created")

        print("🔍 Getting first commit hash...")
        guard let firstCommitHash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }
        print("✅ First commit hash: \(firstCommitHash)")

        print("🔍 Parsing first commit...")
        let firstCommit = testRepository.parseCommit(hash: firstCommitHash)
        XCTAssertNotNil(firstCommit, "Should be able to parse first commit")
        print("✅ First commit parsed, tree hash: \(firstCommit?.treeHash ?? "nil")")

        print("📝 Modifying file...")
        try "Line 1\nLine 2".write(to: testFile, atomically: true, encoding: .utf8)
        print("✅ File modified")

        print("📝 Adding modified file to git...")
        let addProcess2 = Process()
        addProcess2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess2.arguments = ["add", "test.txt"]
        addProcess2.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess2.run()
        addProcess2.waitUntilExit()
        print("✅ Modified file added to git")

        print("📝 Creating second commit...")
        let commitProcess2 = Process()
        commitProcess2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess2.arguments = ["commit", "-m", "Modify file"]
        commitProcess2.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess2.run()
        commitProcess2.waitUntilExit()
        print("✅ Second commit created")

        print("🔍 Getting second commit hash...")
        guard let secondCommitHash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }
        print("✅ Second commit hash: \(secondCommitHash)")

        print("🔍 Parsing second commit...")
        let secondCommit = testRepository.parseCommit(hash: secondCommitHash)
        XCTAssertNotNil(secondCommit, "Should be able to parse second commit")
        print("✅ Second commit parsed, tree hash: \(secondCommit?.treeHash ?? "nil")")

        print("📊 Calculating diff stats...")
        let diffStats = testRepository.getDiffStats(oldTreeHash: firstCommit?.treeHash, newTreeHash: secondCommit!.treeHash)

        print("✅ Diff stats calculated successfully")
        print("  Files changed: \(diffStats.filesChanged)")
        print("  Lines added: \(diffStats.added)")
        print("  Lines removed: \(diffStats.removed)")
    }
}
