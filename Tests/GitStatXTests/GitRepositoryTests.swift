import XCTest
@testable import GitStatX

final class GitRepositoryTests: XCTestCase {
    var testRepository: GitRepository!
    var testRepositoryPath: String!

    override func setUpWithError() throws {
        print("\n🧪 Setting up test...")

        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GitStatXTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        print("📁 Created test directory: \(testDir.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = testDir

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("✅ Git repository initialized successfully")
        } else {
            XCTFail("Failed to initialize git repository")
            return
        }

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

        print("✅ Git config set")

        testRepositoryPath = testDir.path
        testRepository = GitRepository(path: testRepositoryPath)

        XCTAssertNotNil(testRepository, "GitRepository should be initialized")
        print("✅ GitRepository created: \(testRepositoryPath)")
    }

    override func tearDownWithError() throws {
        print("\n🧹 Cleaning up test...")

        if let path = testRepositoryPath {
            try? FileManager.default.removeItem(atPath: path)
            print("✅ Test directory removed")
        }

        testRepository = nil
        testRepositoryPath = nil
    }

    func testCurrentBranch() throws {
        print("\n🧪 Testing currentBranch...")

        let branch = testRepository.currentBranch

        XCTAssertNotNil(branch, "Current branch should not be nil")
        XCTAssertEqual(branch, "main", "Default branch should be 'main'")

        print("✅ Current branch test passed: \(branch ?? "nil")")
    }

    func testCurrentCommitHash() throws {
        print("\n🧪 Testing currentCommitHash...")

        let hash = testRepository.currentCommitHash

        XCTAssertNil(hash, "Current commit hash should be nil for empty repository")

        print("✅ Current commit hash test passed: \(hash ?? "nil")")
    }

    func testCreateCommit() throws {
        print("\n🧪 Testing commit creation...")

        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Hello, World!".write(to: testFile, atomically: true, encoding: .utf8)

        print("📝 Created test file")

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()

        XCTAssertEqual(addProcess.terminationStatus, 0, "Git add should succeed")

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Initial commit"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        XCTAssertEqual(commitProcess.terminationStatus, 0, "Git commit should succeed")

        print("✅ Commit created")

        let hash = testRepository.currentCommitHash

        XCTAssertNotNil(hash, "Current commit hash should not be nil after commit")
        XCTAssertEqual(hash?.count, 40, "Commit hash should be 40 characters")

        print("✅ Commit hash: \(hash ?? "nil")")
    }

    func testGetAllCommits() throws {
        print("\n🧪 Testing getAllCommits...")

        let commits = testRepository.getAllCommits()

        XCTAssertEqual(commits.count, 0, "Should have 0 commits in empty repository")

        print("✅ Empty repository has 0 commits")

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

        print("✅ Created first commit")

        let commitsAfterFirst = testRepository.getAllCommits()

        XCTAssertEqual(commitsAfterFirst.count, 1, "Should have 1 commit after first commit")
        XCTAssertEqual(commitsAfterFirst.first?.authorName, "Test User", "Author name should match")
        XCTAssertEqual(commitsAfterFirst.first?.authorEmail, "test@example.com", "Author email should match")
        XCTAssertEqual(commitsAfterFirst.first?.message, "Initial commit", "Commit message should match")

        print("✅ First commit verified")

        try "Second line".write(to: testFile, atomically: true, encoding: .utf8)

        let addProcess2 = Process()
        addProcess2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess2.arguments = ["add", "test.txt"]
        addProcess2.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess2.run()
        addProcess2.waitUntilExit()

        let commitProcess2 = Process()
        commitProcess2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess2.arguments = ["commit", "-m", "Second commit"]
        commitProcess2.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess2.run()
        commitProcess2.waitUntilExit()

        print("✅ Created second commit")

        let commitsAfterSecond = testRepository.getAllCommits()

        XCTAssertEqual(commitsAfterSecond.count, 2, "Should have 2 commits after second commit")

        print("✅ Second commit verified")
        print("📊 Total commits: \(commitsAfterSecond.count)")
    }

    func testParseCommit() throws {
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
        commitProcess.arguments = ["commit", "-m", "Test commit message"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        guard let hash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }

        let commit = testRepository.parseCommit(hash: hash)

        XCTAssertNotNil(commit, "Should be able to parse commit")
        XCTAssertEqual(commit?.hash, hash, "Commit hash should match")
        XCTAssertEqual(commit?.authorName, "Test User", "Author name should match")
        XCTAssertEqual(commit?.authorEmail, "test@example.com", "Author email should match")
        XCTAssertEqual(commit?.message, "Test commit message", "Commit message should match")
        XCTAssertNotNil(commit?.authorDate, "Author date should not be nil")
        XCTAssertNotNil(commit?.committerDate, "Committer date should not be nil")

        print("✅ Commit parsed successfully")
        print("  Hash: \(hash)")
        print("  Author: \(commit?.authorName ?? "nil") <\(commit?.authorEmail ?? "nil")>")
        print("  Message: \(commit?.message ?? "nil")")
    }

    func testParseTree() throws {
        print("\n🧪 Testing parseTree...")

        let testFile1 = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("file1.txt")
        let testFile2 = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("file2.txt")

        try "Content 1".write(to: testFile1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: testFile2, atomically: true, encoding: .utf8)

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "."]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Add files"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        guard let hash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }

        let commit = testRepository.parseCommit(hash: hash)
        XCTAssertNotNil(commit, "Should be able to parse commit")

        let tree = testRepository.parseTree(hash: commit!.treeHash)
        XCTAssertNotNil(tree, "Should be able to parse tree")
        XCTAssertEqual(tree?.entries.count, 2, "Tree should have 2 entries")

        print("✅ Tree parsed successfully")
        print("  Tree hash: \(commit!.treeHash)")
        print("  Entries: \(tree?.entries.count ?? 0)")
        for entry in tree?.entries ?? [] {
            print("    - \(entry.path) (\(entry.type))")
        }
    }

    func testParseBlob() throws {
        print("\n🧪 Testing parseBlob...")

        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        let testContent = "Hello, World!\nThis is a test file."
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Add test file"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        guard let commitHash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }

        let commit = testRepository.parseCommit(hash: commitHash)
        XCTAssertNotNil(commit, "Should be able to parse commit")

        let tree = testRepository.parseTree(hash: commit!.treeHash)
        XCTAssertNotNil(tree, "Should be able to parse tree")

        guard let testEntry = tree?.entries.first(where: { $0.path == "test.txt" }) else {
            XCTFail("Should find test.txt in tree")
            return
        }

        let blob = testRepository.parseBlob(hash: testEntry.hash)
        XCTAssertNotNil(blob, "Should be able to parse blob")
        XCTAssertEqual(blob?.hash, testEntry.hash, "Blob hash should match")

        let blobContent = String(data: blob!.data, encoding: .utf8)
        XCTAssertEqual(blobContent, testContent, "Blob content should match")

        print("✅ Blob parsed successfully")
        print("  Blob hash: \(testEntry.hash)")
        print("  Content: \(blobContent ?? "nil")")
    }

    func testGetDiffStats() throws {
        print("\n🧪 Testing getDiffStats...")

        print("📝 Creating initial file...")
        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Initial content".write(to: testFile, atomically: true, encoding: .utf8)
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
        try "Modified content\nNew line".write(to: testFile, atomically: true, encoding: .utf8)
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

        XCTAssertGreaterThan(diffStats.filesChanged, 0, "Should have at least 1 file changed")
        XCTAssertGreaterThanOrEqual(diffStats.added, 0, "Added lines should be non-negative")
        XCTAssertGreaterThanOrEqual(diffStats.removed, 0, "Removed lines should be non-negative")

        print("✅ Diff stats calculated successfully")
        print("  Files changed: \(diffStats.filesChanged)")
        print("  Lines added: \(diffStats.added)")
        print("  Lines removed: \(diffStats.removed)")
    }

    func testMultipleBranches() throws {
        print("\n🧪 Testing multiple branches...")

        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Main branch content".write(to: testFile, atomically: true, encoding: .utf8)

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Main commit"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()

        let branchProcess = Process()
        branchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        branchProcess.arguments = ["checkout", "-b", "feature"]
        branchProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try branchProcess.run()
        branchProcess.waitUntilExit()

        try "Feature branch content".write(to: testFile, atomically: true, encoding: .utf8)

        let addProcess2 = Process()
        addProcess2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess2.arguments = ["add", "test.txt"]
        addProcess2.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess2.run()
        addProcess2.waitUntilExit()

        let commitProcess2 = Process()
        commitProcess2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess2.arguments = ["commit", "-m", "Feature commit"]
        commitProcess2.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess2.run()
        commitProcess2.waitUntilExit()

        let branch = testRepository.currentBranch
        XCTAssertEqual(branch, "feature", "Current branch should be 'feature'")

        let commits = testRepository.getAllCommits()
        XCTAssertEqual(commits.count, 2, "Should have 2 commits")

        print("✅ Multiple branches test passed")
        print("  Current branch: \(branch ?? "nil")")
        print("  Total commits: \(commits.count)")
    }
}
