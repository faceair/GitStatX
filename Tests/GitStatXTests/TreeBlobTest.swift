import XCTest
@testable import GitStatX

final class TreeBlobTest: XCTestCase {
    var testRepository: GitRepository!
    var testRepositoryPath: String!

    override func setUpWithError() throws {
        print("\n🧪 Setting up tree/blob test...")

        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GitStatXTreeBlobTest_\(UUID().uuidString)")
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

        print("✅ Setup complete")
    }

    override func tearDownWithError() throws {
        if let path = testRepositoryPath {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    func testParseTreeAndBlob() throws {
        print("\n🧪 Testing parseTree and parseBlob...")

        print("📝 Creating test file...")
        let testFile = URL(fileURLWithPath: testRepositoryPath).appendingPathComponent("test.txt")
        try "Line 1\nLine 2".write(to: testFile, atomically: true, encoding: .utf8)
        print("✅ Test file created")

        print("📝 Adding file to git...")
        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "test.txt"]
        addProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try addProcess.run()
        addProcess.waitUntilExit()
        print("✅ File added to git")

        print("📝 Creating commit...")
        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "Test commit"]
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: testRepositoryPath)
        try commitProcess.run()
        commitProcess.waitUntilExit()
        print("✅ Commit created")

        print("🔍 Getting commit hash...")
        guard let commitHash = testRepository.currentCommitHash else {
            XCTFail("Should have a commit hash")
            return
        }
        print("✅ Commit hash: \(commitHash)")

        print("🔍 Parsing commit...")
        guard let commit = testRepository.parseCommit(hash: commitHash) else {
            XCTFail("Should be able to parse commit")
            return
        }
        print("✅ Commit parsed, tree hash: \(commit.treeHash)")

        print("🔍 Parsing tree...")
        guard let tree = testRepository.parseTree(hash: commit.treeHash) else {
            XCTFail("Should be able to parse tree")
            return
        }
        print("✅ Tree parsed, entries: \(tree.entries.count)")

        for entry in tree.entries {
            print("  📁 Entry: \(entry.path) (\(entry.type)) hash: \(entry.hash)")

            if entry.type == "blob" {
                print("  🔍 Parsing blob...")
                guard let blob = testRepository.parseBlob(hash: entry.hash) else {
                    XCTFail("Should be able to parse blob")
                    return
                }
                print("  ✅ Blob parsed, size: \(blob.data.count) bytes")

                if let content = String(data: blob.data, encoding: .utf8) {
                    print("  📄 Content: \(content)")
                }
            }
        }

        print("✅ Test completed successfully")
    }
}
