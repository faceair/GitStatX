import Foundation

struct GitCommit {
    let hash: String
    let treeHash: String
    let parentHashes: [String]
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let committerName: String
    let committerEmail: String
    let committerDate: Date
    let message: String
}

struct GitTreeEntry {
    let mode: String
    let type: String
    let hash: String
    let path: String
}

struct GitTree {
    let hash: String
    let entries: [GitTreeEntry]
}

enum FileChangeKind: String {
    case added
    case removed
    case modified
}

struct GitBlob {
    let hash: String
    let data: Data
}

class GitRepository {
    let path: String
    private let gitPath: String
    private var treeCache: [String: GitTree] = [:]
    private var blobCache: [String: GitBlob] = [:]
    private var lineCountCache: [String: Int] = [:]
    private let cacheLock = NSLock()

    init?(path: String) {
        self.path = path

        let gitPath = URL(fileURLWithPath: path).appendingPathComponent(".git").path

        if FileManager.default.fileExists(atPath: gitPath) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir), isDir.boolValue {
                self.gitPath = gitPath
            } else {
                self.gitPath = path
            }
        } else {
            return nil
        }
    }

    private func runGit(_ arguments: [String]) -> (status: Int32, data: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.arguments = ["git"] + arguments
        process.standardError = Pipe()
        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
        } catch {
            return (1, Data())
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    private func runGitString(_ arguments: [String]) -> String? {
        let result = runGit(arguments)
        guard result.status == 0 else { return nil }
        return String(decoding: result.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        runGit(["rev-parse", "--is-inside-work-tree"]).status == 0
    }

    var currentBranch: String? {
        runGitString(["symbolic-ref", "--quiet", "--short", "HEAD"])
    }

    var currentCommitHash: String? {
        runGitString(["rev-parse", "--verify", "HEAD"])
    }

    func parseCommit(hash: String) -> GitCommit? {
        let format = "%H%x01%T%x01%P%x01%an%x01%ae%x01%at%x01%cn%x01%ce%x01%ct%x01%s%x02"
        let result = runGit(["show", "-s", "--format=\(format)", hash])
        guard result.status == 0 else { return nil }

        let output = String(decoding: result.data, as: UTF8.self)
        guard let payload = output.split(separator: "\u{02}", maxSplits: 1).first else { return nil }
        let parts = payload.split(separator: "\u{01}", maxSplits: 9, omittingEmptySubsequences: false)
        guard parts.count >= 10 else { return nil }

        let parents = parts[2].isEmpty ? [] : parts[2].split(separator: " ").map(String.init)
        let authorDate = Date(timeIntervalSince1970: TimeInterval(String(parts[5])) ?? 0)
        let committerDate = Date(timeIntervalSince1970: TimeInterval(String(parts[8])) ?? 0)
        let message = String(parts[9]).trimmingCharacters(in: .whitespacesAndNewlines)

        return GitCommit(
            hash: String(parts[0]),
            treeHash: String(parts[1]),
            parentHashes: parents,
            authorName: String(parts[3]),
            authorEmail: String(parts[4]),
            authorDate: authorDate,
            committerName: String(parts[6]),
            committerEmail: String(parts[7]),
            committerDate: committerDate,
            message: message
        )
    }

    func parseTree(hash: String) -> GitTree? {
        cacheLock.lock()
        if let cached = treeCache[hash] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = runGit(["ls-tree", "-z", hash])
        guard result.status == 0 else { return nil }

        var entries: [GitTreeEntry] = []
        let chunks = result.data.split(separator: 0)

        for chunk in chunks {
            guard let line = String(data: chunk, encoding: .utf8) else { continue }
            let pieces = line.split(separator: "\t", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let header = pieces[0].split(separator: " ")
            guard header.count == 3 else { continue }

            let mode = String(header[0])
            let type = String(header[1])
            let entryHash = String(header[2])
            let path = String(pieces[1])

            entries.append(GitTreeEntry(mode: mode, type: type, hash: entryHash, path: path))
        }

        let tree = GitTree(hash: hash, entries: entries)
        cacheLock.lock()
        treeCache[hash] = tree
        cacheLock.unlock()
        return tree
    }

    func parseBlob(hash: String) -> GitBlob? {
        cacheLock.lock()
        if let cached = blobCache[hash] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = runGit(["cat-file", "-p", hash])
        guard result.status == 0 else { return nil }

        let blob = GitBlob(hash: hash, data: result.data)
        cacheLock.lock()
        blobCache[hash] = blob
        cacheLock.unlock()
        return blob
    }

    func flattenTreeEntries(hash: String) -> [GitTreeEntry] {
        var result: [GitTreeEntry] = []
        var stack: [(hash: String, prefix: String)] = [(hash, "")]

        while let current = stack.popLast() {
            guard let tree = parseTree(hash: current.hash) else { continue }

            for entry in tree.entries {
                let fullPath = current.prefix.isEmpty ? entry.path : "\(current.prefix)/\(entry.path)"
                if entry.type == "tree" {
                    stack.append((entry.hash, fullPath))
                } else {
                    result.append(GitTreeEntry(mode: entry.mode, type: entry.type, hash: entry.hash, path: fullPath))
                }
            }
        }

        return result
    }

    private func lineCount(forBlobHash hash: String) -> Int {
        cacheLock.lock()
        if let cached = lineCountCache[hash] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let blob = parseBlob(hash: hash) else {
            cacheLock.lock()
            lineCountCache[hash] = 0
            cacheLock.unlock()
            return 0
        }

        let count = blob.data.reduce(0) { $0 + ($1 == 0x0a ? 1 : 0) }
        cacheLock.lock()
        lineCountCache[hash] = count
        cacheLock.unlock()
        return count
    }

    struct ParsedCommitNumstat {
        let commit: GitCommit
        let numstats: [(path: String, added: Int, removed: Int)]
    }

    struct ParsedCommitShortstat {
        let commit: GitCommit
        let filesChanged: Int
        let added: Int
        let removed: Int
    }

    func getCommitsWithNumstat(since: String? = nil, progress: ((Int, Int) -> Void)? = nil) -> [ParsedCommitNumstat] {
        var arguments = [
            "-c", "log.showSignature=false",
            "log",
            "--all",
            "--reverse",
            "--no-renames",
            "--no-decorate",
            "--no-color",
            "--date=unix",
            "--numstat",
            "--format=%H%x01%T%x01%P%x01%an%x01%ae%x01%at%x01%cn%x01%ce%x01%ct%x01%s%x02"
        ]

        if let since = since {
            arguments.insert("\(since)..HEAD", at: 2)
        }

        let result = runGit(arguments)
        guard result.status == 0 else { return [] }

        let text = String(decoding: result.data, as: UTF8.self)
        var results: [ParsedCommitNumstat] = []

        var currentCommit: GitCommit?
        var currentNumstats: [(String, Int, Int)] = []

        var index = 0
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let totalCommits = lines.filter { $0.contains("\u{02}") }.count

        for line in lines {
            if line.contains("\u{02}") {
                if let commit = currentCommit {
                    results.append(ParsedCommitNumstat(commit: commit, numstats: currentNumstats))
                    currentNumstats.removeAll(keepingCapacity: true)
                }

                let header = line.replacingOccurrences(of: "\u{02}", with: "")
                let parts = header.split(separator: "\u{01}", omittingEmptySubsequences: false)
                guard parts.count >= 10 else { continue }

                let hash = String(parts[0])
                let tree = String(parts[1])
                let parents = parts[2].isEmpty ? [] : parts[2].split(separator: " ").map(String.init)
                let authorName = String(parts[3])
                let authorEmail = String(parts[4])
                let authorDateStr = String(parts[5])
                let committerName = String(parts[6])
                let committerEmail = String(parts[7])
                let committerDateStr = String(parts[8])
                let message = String(parts[9])

                let authorDate = Date(timeIntervalSince1970: TimeInterval(authorDateStr) ?? 0)
                let committerDate = Date(timeIntervalSince1970: TimeInterval(committerDateStr) ?? authorDate.timeIntervalSince1970)

                currentCommit = GitCommit(
                    hash: hash,
                    treeHash: tree,
                    parentHashes: parents,
                    authorName: authorName,
                    authorEmail: authorEmail,
                    authorDate: authorDate,
                    committerName: committerName,
                    committerEmail: committerEmail,
                    committerDate: committerDate,
                    message: message
                )
                index += 1
                if index % 50 == 0 || index == totalCommits {
                    progress?(index, totalCommits)
                }
            } else if line.isEmpty {
                continue
            } else if line.contains("\t") {
                let fields = line.split(separator: "\t", maxSplits: 2)
                guard fields.count == 3 else { continue }
                let added = Int(fields[0]) ?? 0
                let removed = Int(fields[1]) ?? 0
                let path = String(fields[2])
                currentNumstats.append((path, added, removed))
            }
        }

        if let commit = currentCommit {
            results.append(ParsedCommitNumstat(commit: commit, numstats: currentNumstats))
        }

        return results
    }

    func getCommitsWithShortstat(since: String? = nil, progress: ((Int, Int) -> Void)? = nil) -> [ParsedCommitShortstat] {
        var arguments = [
            "-c", "log.showSignature=false",
            "log",
            "--all",
            "--reverse",
            "--no-renames",
            "--no-decorate",
            "--no-color",
            "--date=unix",
            "--shortstat",
            "--format=%H%x01%T%x01%P%x01%an%x01%ae%x01%at%x01%cn%x01%ce%x01%ct%x01%s%x02"
        ]

        if let since = since {
            arguments.insert("\(since)..HEAD", at: 4)
        }

        let result = runGit(arguments)
        guard result.status == 0 else { return [] }

        let text = String(decoding: result.data, as: UTF8.self)
        var results: [ParsedCommitShortstat] = []

        var currentCommit: GitCommit?
        var filesChanged = 0
        var added = 0
        var removed = 0

        var index = 0
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let totalCommits = lines.filter { $0.contains("\u{02}") }.count

        for line in lines {
            if line.contains("\u{02}") {
                if let commit = currentCommit {
                    results.append(ParsedCommitShortstat(commit: commit, filesChanged: filesChanged, added: added, removed: removed))
                    filesChanged = 0
                    added = 0
                    removed = 0
                }

                let header = line.replacingOccurrences(of: "\u{02}", with: "")
                let parts = header.split(separator: "\u{01}", omittingEmptySubsequences: false)
                guard parts.count >= 10 else { continue }

                let parents = parts[2].isEmpty ? [] : parts[2].split(separator: " ").map(String.init)
                let authorDate = Date(timeIntervalSince1970: TimeInterval(String(parts[5])) ?? 0)
                let committerDate = Date(timeIntervalSince1970: TimeInterval(String(parts[8])) ?? authorDate.timeIntervalSince1970)

                currentCommit = GitCommit(
                    hash: String(parts[0]),
                    treeHash: String(parts[1]),
                    parentHashes: parents,
                    authorName: String(parts[3]),
                    authorEmail: String(parts[4]),
                    authorDate: authorDate,
                    committerName: String(parts[6]),
                    committerEmail: String(parts[7]),
                    committerDate: committerDate,
                    message: String(parts[9])
                )
                index += 1
                if index % 50 == 0 || index == totalCommits {
                    progress?(index, totalCommits)
                }
            } else if line.contains("files changed") {
                let numbers = line.split(whereSeparator: { !$0.isNumber && $0 != "-" })
                if numbers.count >= 3 {
                    filesChanged = Int(numbers[0]) ?? 0
                    added = Int(numbers[1]) ?? 0
                    removed = Int(numbers[2]) ?? 0
                }
            }
        }

        if let commit = currentCommit {
            results.append(ParsedCommitShortstat(commit: commit, filesChanged: filesChanged, added: added, removed: removed))
        }

        return results
    }

    func getAllCommits(progress: ((Int, Int) -> Void)? = nil) -> [GitCommit] {
        let result = runGit([
            "-c", "log.showSignature=false",
            "log",
            "--all",
            "--reverse",
            "--no-renames",
            "--no-decorate",
            "--no-color",
            "--date=unix",
            "--format=%H%x01%T%x01%P%x01%an%x01%ae%x01%at%x01%cn%x01%ce%x01%ct%x01%s%x02"
        ])

        guard result.status == 0 else { return [] }

        let text = String(decoding: result.data, as: UTF8.self)
        var commits: [GitCommit] = []
        let lines = text.split(whereSeparator: \.isNewline)
        let total = lines.count

        for (idx, line) in lines.enumerated() {
            let header = line.replacingOccurrences(of: "\u{02}", with: "")
            let parts = header.split(separator: "\u{01}", omittingEmptySubsequences: false)
            guard parts.count >= 10 else { continue }

            let parents = parts[2].isEmpty ? [] : parts[2].split(separator: " ").map(String.init)
            let authorDate = Date(timeIntervalSince1970: TimeInterval(String(parts[5])) ?? 0)
            let committerDate = Date(timeIntervalSince1970: TimeInterval(String(parts[8])) ?? authorDate.timeIntervalSince1970)

            let commit = GitCommit(
                hash: String(parts[0]),
                treeHash: String(parts[1]),
                parentHashes: parents,
                authorName: String(parts[3]),
                authorEmail: String(parts[4]),
                authorDate: authorDate,
                committerName: String(parts[6]),
                committerEmail: String(parts[7]),
                committerDate: committerDate,
                message: String(parts[9])
            )
            commits.append(commit)

            if idx % 50 == 0 || idx + 1 == total {
                progress?(idx + 1, total)
            }
        }

        return commits
    }

    func getDiffStats(oldTreeHash: String?, newTreeHash: String) -> (added: Int, removed: Int, filesChanged: Int) {
        let details = getDiffDetails(oldTreeHash: oldTreeHash, newTreeHash: newTreeHash)
        return (details.added, details.removed, details.filesChanged)
    }

    func getDiffDetails(oldTreeHash: String?, newTreeHash: String) -> (added: Int, removed: Int, filesChanged: Int, perFile: [String: (added: Int, removed: Int, kind: FileChangeKind)]) {
        let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        let base = oldTreeHash ?? emptyTree
        let result = runGit(["diff", "--numstat", base, newTreeHash])
        guard result.status == 0 else {
            return (0, 0, 0, [:])
        }

        let text = String(decoding: result.data, as: UTF8.self)
        var added = 0
        var removed = 0
        var perFile: [String: (added: Int, removed: Int, kind: FileChangeKind)] = [:]

        let lines = text.split(whereSeparator: \.isNewline)
        for line in lines {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let addedValue = Int(fields[0]) ?? 0
            let removedValue = Int(fields[1]) ?? 0
            let path = String(fields[2])

            added += addedValue
            removed += removedValue

            let kind: FileChangeKind
            if addedValue > 0 && removedValue == 0 {
                kind = .added
            } else if addedValue == 0 && removedValue > 0 {
                kind = .removed
            } else {
                kind = .modified
            }
            perFile[path] = (addedValue, removedValue, kind)
        }

        return (added, removed, perFile.count, perFile)
    }

    func calculateSnapshotStats(treeHash: String) -> (files: Int, lines: Int, extensions: [String: (files: Int, lines: Int)]) {
        let lsResult = runGit(["ls-tree", "-r", "-z", treeHash])
        guard lsResult.status == 0 else { return (0, 0, [:]) }

        let entries = lsResult.data.split(separator: 0)
        var blobs: [(hash: String, path: String)] = []

        for entry in entries {
            guard let line = String(data: entry, encoding: .utf8) else { continue }
            let pieces = line.split(separator: "\t", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let header = pieces[0].split(separator: " ")
            guard header.count == 3, header[1] == "blob" else { continue }

            let hash = String(header[2])
            let path = String(pieces[1])
            blobs.append((hash, path))
        }

        guard !blobs.isEmpty else { return (0, 0, [:]) }

        let batchProcess = Process()
        batchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        batchProcess.currentDirectoryURL = URL(fileURLWithPath: path)
        batchProcess.arguments = ["git", "cat-file", "--batch"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        batchProcess.standardInput = inputPipe
        batchProcess.standardOutput = outputPipe
        batchProcess.standardError = Pipe()

        do {
            try batchProcess.run()
        } catch {
            return (blobs.count, 0, [:])
        }

        let request = blobs.map { "\($0.hash)\n" }.joined()
        if let data = request.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        let batchData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        batchProcess.waitUntilExit()

        var offset = batchData.startIndex
        var totalLines = 0
        var extensions: [String: (files: Int, lines: Int)] = [:]

        for entry in blobs {
            guard let headerEnd = batchData[offset...].firstIndex(of: 0x0a) else { break }
            let headerData = batchData[offset..<headerEnd]
            offset = batchData.index(after: headerEnd)

            guard let header = String(data: headerData, encoding: .utf8) else { break }
            let headerParts = header.split(separator: " ")
            guard headerParts.count >= 3, let size = Int(headerParts[2]) else { break }

            guard let contentEnd = batchData.index(offset, offsetBy: size, limitedBy: batchData.endIndex) else { break }
            let content = batchData[offset..<contentEnd]
            offset = contentEnd
            if offset < batchData.endIndex {
                offset = batchData.index(after: offset)
            }

            let lineCount = content.reduce(0) { $0 + ($1 == 0x0a ? 1 : 0) }
            totalLines += lineCount

            let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            let key = ext.isEmpty ? "no-extension" : ext
            var stats = extensions[key] ?? (0, 0)
            stats.files += 1
            stats.lines += lineCount
            extensions[key] = stats
        }

        return (blobs.count, totalLines, extensions)
    }
}
