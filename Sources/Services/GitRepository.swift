import Foundation

struct GitCommit {
    let hash: String
    let treeHash: String
    let parentHashes: [String]
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let authorTimeZoneOffsetMinutes: Int?
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

struct GitTag {
    let name: String
    let commitHash: String
    let date: Date?
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

    private func parseTimezoneOffsetMinutes(_ isoString: String) -> Int? {
        if isoString.hasSuffix("Z") {
            return 0
        }
        guard isoString.count >= 6 else { return nil }
        let suffix = isoString.suffix(6)
        guard let sign = suffix.first, sign == "+" || sign == "-" else { return nil }
        let parts = suffix.dropFirst().split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let total = hours * 60 + minutes
        return sign == "-" ? -total : total
    }

    var currentBranch: String? {
        runGitString(["symbolic-ref", "--quiet", "--short", "HEAD"])
    }

    var currentCommitHash: String? {
        runGitString(["rev-parse", "--verify", "HEAD"])
    }

    func parseCommit(hash: String) -> GitCommit? {
        let format = "%H%x01%T%x01%P%x01%an%x01%ae%x01%at%x01%aI%x01%cn%x01%ce%x01%ct%x01%cI%x01%s%x02"
        let result = runGit(["show", "-s", "--format=\(format)", hash])
        guard result.status == 0 else { return nil }

        let output = String(decoding: result.data, as: UTF8.self)
        guard let payload = output.split(separator: "\u{02}", maxSplits: 1).first else { return nil }
        let parts = payload.split(separator: "\u{01}", maxSplits: 11, omittingEmptySubsequences: false)
        guard parts.count >= 12 else { return nil }

        let parents = parts[2].isEmpty ? [] : parts[2].split(separator: " ").map(String.init)
        let authorDate = Date(timeIntervalSince1970: TimeInterval(String(parts[5])) ?? 0)
        let authorISO = String(parts[6])
        let committerDate = Date(timeIntervalSince1970: TimeInterval(String(parts[9])) ?? 0)
        let message = String(parts[11]).trimmingCharacters(in: .whitespacesAndNewlines)

        return GitCommit(
            hash: String(parts[0]),
            treeHash: String(parts[1]),
            parentHashes: parents,
            authorName: String(parts[3]),
            authorEmail: String(parts[4]),
            authorDate: authorDate,
            authorTimeZoneOffsetMinutes: parseTimezoneOffsetMinutes(authorISO),
            committerName: String(parts[7]),
            committerEmail: String(parts[8]),
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

    struct ParsedCommitNumstat {
        let commit: GitCommit
        let numstats: [(path: String, added: Int, removed: Int)]
    }

    func getCommitsWithNumstat(since: String? = nil) -> [ParsedCommitNumstat] {
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
            "--format=%H%x01%T%x01%P%x01%an%x01%ae%x01%at%x01%aI%x01%cn%x01%ce%x01%ct%x01%cI%x01%s%x02"
        ]

        if let since = since {
            arguments.insert("\(since)..HEAD", at: 3)
        }

        let result = runGit(arguments)
        guard result.status == 0 else { return [] }

        let text = String(decoding: result.data, as: UTF8.self)
        var results: [ParsedCommitNumstat] = []

        var currentCommit: GitCommit?
        var currentNumstats: [(String, Int, Int)] = []

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for line in lines {
            if line.contains("\u{02}") {
                if let commit = currentCommit {
                    results.append(ParsedCommitNumstat(commit: commit, numstats: currentNumstats))
                    currentNumstats.removeAll(keepingCapacity: true)
                }

                let header = line.replacingOccurrences(of: "\u{02}", with: "")
                let parts = header.split(separator: "\u{01}", omittingEmptySubsequences: false)
                guard parts.count >= 12 else { continue }

                let hash = String(parts[0])
                let tree = String(parts[1])
                let parents = parts[2].isEmpty ? [] : parts[2].split(separator: " ").map(String.init)
                let authorName = String(parts[3])
                let authorEmail = String(parts[4])
                let authorDateStr = String(parts[5])
                let authorISO = String(parts[6])
                let committerName = String(parts[7])
                let committerEmail = String(parts[8])
                let committerDateStr = String(parts[9])
                let message = String(parts[11])

                let authorDate = Date(timeIntervalSince1970: TimeInterval(authorDateStr) ?? 0)
                let committerDate = Date(timeIntervalSince1970: TimeInterval(committerDateStr) ?? authorDate.timeIntervalSince1970)

                currentCommit = GitCommit(
                    hash: hash,
                    treeHash: tree,
                    parentHashes: parents,
                    authorName: authorName,
                    authorEmail: authorEmail,
                    authorDate: authorDate,
                    authorTimeZoneOffsetMinutes: parseTimezoneOffsetMinutes(authorISO),
                    committerName: committerName,
                    committerEmail: committerEmail,
                    committerDate: committerDate,
                    message: message
                )
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

    func getAllCommits() -> [GitCommit] {
        let result = runGit([
            "-c", "log.showSignature=false",
            "log",
            "--all",
            "--reverse",
            "--no-renames",
            "--no-decorate",
            "--no-color",
            "--date=unix",
            "--format=%H%x01%T%x01%P%x01%an%x01%ae%x01%at%x01%aI%x01%cn%x01%ce%x01%ct%x01%cI%x01%s%x02"
        ])

        guard result.status == 0 else { return [] }

        let text = String(decoding: result.data, as: UTF8.self)
        var commits: [GitCommit] = []
        let lines = text.split(whereSeparator: \.isNewline)

        for line in lines {
            let header = line.replacingOccurrences(of: "\u{02}", with: "")
            let parts = header.split(separator: "\u{01}", omittingEmptySubsequences: false)
            guard parts.count >= 12 else { continue }

            let parents = parts[2].isEmpty ? [] : parts[2].split(separator: " ").map(String.init)
            let authorDate = Date(timeIntervalSince1970: TimeInterval(String(parts[5])) ?? 0)
            let authorISO = String(parts[6])
            let committerDate = Date(timeIntervalSince1970: TimeInterval(String(parts[9])) ?? authorDate.timeIntervalSince1970)

            let commit = GitCommit(
                hash: String(parts[0]),
                treeHash: String(parts[1]),
                parentHashes: parents,
                authorName: String(parts[3]),
                authorEmail: String(parts[4]),
                authorDate: authorDate,
                authorTimeZoneOffsetMinutes: parseTimezoneOffsetMinutes(authorISO),
                committerName: String(parts[7]),
                committerEmail: String(parts[8]),
                committerDate: committerDate,
                message: String(parts[11])
            )
            commits.append(commit)
        }

        return commits
    }

    func getTags() -> [GitTag] {
        let format = "%(refname:short)%09%(creatordate:unix)%09%(objectname)"
        let result = runGit([
            "for-each-ref",
            "--sort=creatordate",
            "--format=\(format)",
            "refs/tags"
        ])

        guard result.status == 0 else { return [] }

        let raw = String(decoding: result.data, as: UTF8.self)
        let normalized = raw.replacingOccurrences(of: "%x01", with: "\t").replacingOccurrences(of: "%09", with: "\t")
        let lines = normalized.split(whereSeparator: \.isNewline)

        var tags: [GitTag] = []

        for line in lines {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard !parts.isEmpty else { continue }
            let name = String(parts[0])
            let dateStr = parts.count > 1 ? String(parts[1]) : ""
            let commitHash = parts.count > 2 ? String(parts[2]) : name
            let date: Date?
            if let ts = TimeInterval(dateStr) {
                date = Date(timeIntervalSince1970: ts)
            } else {
                // 如果 creatordate 不可用，使用 tag 所指向提交的日期作为替代
                let dateResult = runGit(["log", "-1", "--format=%ct", name])
                if dateResult.status == 0, let ts = TimeInterval(String(decoding: dateResult.data, as: UTF8.self)) {
                    date = Date(timeIntervalSince1970: ts)
                } else {
                    date = nil
                }
            }
            tags.append(GitTag(name: name, commitHash: commitHash, date: date))
        }

        return tags
    }

}
