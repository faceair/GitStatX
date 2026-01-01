import SwiftData
import Foundation
import CryptoKit

@Model
final class Project {
    var name: String?
    var path: String?
    var projectType: String?
    var isFolder: Bool
    var listOrder: Int
    var expanded: Bool
    var isGeneratingStats: Bool
    var isRenaming: Bool
    var lastGeneratedCommit: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Project.children)
    var parent: Project?

    @Relationship(deleteRule: .cascade)
    var children: [Project]?

    init(name: String? = nil, path: String? = nil, projectType: String? = nil, isFolder: Bool = false, listOrder: Int = 0, parent: Project? = nil, expanded: Bool = false) {
        self.name = name
        self.path = path
        self.projectType = projectType
        self.isFolder = isFolder
        self.listOrder = listOrder
        self.expanded = expanded
        self.isGeneratingStats = false
        self.isRenaming = false
        self.lastGeneratedCommit = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.parent = parent
    }

    var displayName: String {
        name ?? URL(fileURLWithPath: path ?? "").lastPathComponent
    }

    var statsPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("GitStatX")
        let reportsDirectory = appDirectory.appendingPathComponent("Reports")
        let projectDirectory = reportsDirectory.appendingPathComponent(statsKey)

        try? FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        return projectDirectory.path
    }

    var identifier: String {
        String(describing: persistentModelID)
    }

    private var statsKey: String {
        guard let path, !path.isEmpty else { return identifier }
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var statsIndexPath: String {
        URL(fileURLWithPath: statsPath).appendingPathComponent("index.html").path
    }

    var statsExists: Bool {
        FileManager.default.fileExists(atPath: statsIndexPath)
    }
}
