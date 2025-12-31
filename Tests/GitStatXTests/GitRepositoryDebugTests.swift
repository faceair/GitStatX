import XCTest
@testable import GitStatX

final class GitRepositoryDebugTests: XCTestCase {
    var testRepository: GitRepository!
    var testRepositoryPath: String!

    override func setUpWithError() throws {
        print("\n🧪 Setting up debug test...")

        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GitStatXDebugTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

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
    }

    override func tearDownWithError() throws {
        if let path = testRepositoryPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        testRepository = nil
        testRepositoryPath = nil
    }

    func testDebugParseBlob() throws {
        print("\n🧪 Testing parseBlob...")

        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Hello, World!".write(to: testFile, atomically: true, encoding: .utf8)

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Initial commit"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        guard let hash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }

        print("📦 Commit hash: \(hash)")

        guard let commit = testRepository.parseCommit(hash: hash) else {
            XCTFail("Should parse commit")
            return
        }

        guard let tree = testRepository.parseTree(hash: commit.treeHash) else {
            XCTFail("Should parse tree")
            return
        }

        guard let entry = tree.entries.first(where: { $0.path == "test.txt" }) else {
            XCTFail("Should find test.txt entry")
            return
        }

        let blob = testRepository.parseBlob(hash: entry.hash)

        XCTAssertNotNil(blob, "Should be able to read blob via git cat-file")
        print("📦 Blob size: \(blob?.data.count ?? 0)")

        if let blob = blob, let content = String(data: blob.data, encoding: .utf8) {
            print("📦 Blob preview: \(content.prefix(200))")
        }
    }

    func testDebugParseCommit() throws {
        print("\n🧪 Testing parseCommit...")

        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Hello, World!".write(to: testFile, atomically: true, encoding: .utf8)

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Initial commit"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        guard let hash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }

        print("📦 Commit hash: \(hash)")

        let commit = testRepository.parseCommit(hash: hash)

        if let commit = commit {
            print("✅ Commit parsed successfully")
            print("  Hash: \(commit.hash)")
            print("  Tree: \(commit.treeHash)")
            print("  Parents: \(commit.parentHashes)")
            print("  Author: \(commit.authorName) <\(commit.authorEmail)>")
            print("  Committer: \(commit.committerName) <\(commit.committerEmail)>")
            print("  Message: \(commit.message)")
        } else {
            print("❌ Failed to parse commit")
        }

        XCTAssertNotNil(commit, "Should be able to parse commit")
    }

    func testDebugGetAllCommits() throws {
        print("\n🧪 Testing getAllCommits...")

        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Hello, World!".write(to: testFile, atomically: true, encoding: .utf8)

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Initial commit"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        print("✅ Commit created")

        let branch = testRepository.currentBranch
        print("📦 Current branch: \(branch ?? "nil")")

        let currentHash = testRepository.currentCommitHash
        print("📦 Current commit hash: \(currentHash ?? "nil")")

        let commits = testRepository.getAllCommits()
        print("📦 Total commits: \(commits.count)")

        for (index, commit) in commits.enumerated() {
            print("  Commit \(index + 1): \(commit.hash)")
            print("    Author: \(commit.authorName) <\(commit.authorEmail)>")
            print("    Message: \(commit.message)")
        }

        XCTAssertEqual(commits.count, 1, "Should have 1 commit")
    }
}
