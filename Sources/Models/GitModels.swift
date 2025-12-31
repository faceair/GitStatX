import SwiftData
import Foundation

@Model
final class Author {
    var name: String
    var email: String
    var commitsCount: Int
    var linesAdded: Int
    var linesRemoved: Int
    var firstCommitDate: Date?
    var lastCommitDate: Date?
    var project: Project?

    init(name: String, email: String, commitsCount: Int = 0, linesAdded: Int = 0, linesRemoved: Int = 0) {
        self.name = name
        self.email = email
        self.commitsCount = commitsCount
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

@Model
final class Commit {
    var commitHash: String
    var authorName: String
    var authorEmail: String
    var authorDate: Date
    var committerName: String
    var committerEmail: String
    var committerDate: Date
    var message: String
    var linesAdded: Int
    var linesRemoved: Int
    var filesChanged: Int
    var project: Project?
    
    init(commitHash: String, authorName: String, authorEmail: String, authorDate: Date, committerName: String, committerEmail: String, committerDate: Date, message: String, linesAdded: Int = 0, linesRemoved: Int = 0, filesChanged: Int = 0) {
        self.commitHash = commitHash
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.committerDate = committerDate
        self.message = message
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.filesChanged = filesChanged
    }
}

@Model
final class File {
    var path: String
    var commitsCount: Int
    var linesAdded: Int
    var linesRemoved: Int

    @Relationship(inverse: \Project.files)
    var project: Project?

    init(path: String, commitsCount: Int = 0, linesAdded: Int = 0, linesRemoved: Int = 0) {
        self.path = path
        self.commitsCount = commitsCount
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}
