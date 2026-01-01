import SwiftData
import Foundation
import Observation

@MainActor
class DataController: Observable {
    let container: ModelContainer
    
    init() {
        let schema = Schema([Project.self])
        let storeURL = Self.defaultStoreURL()
        
        do {
            container = try Self.makeContainer(schema: schema, storeURL: storeURL)
        } catch {
            try? FileManager.default.removeItem(at: storeURL)
            
            do {
                container = try Self.makeContainer(schema: schema, storeURL: storeURL)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

        resetStuckProjects()
    }

    private static func makeContainer(schema: Schema, storeURL: URL) throws -> ModelContainer {
        let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }

    private static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("GitStatX")
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("default.store")
    }
    
    var context: ModelContext {
        return container.mainContext
    }
    
    func fetchRootProjects() -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.parent == nil
            },
            sortBy: [SortDescriptor(\.listOrder)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func addProject(name: String? = nil, path: String? = nil, projectType: String? = nil, isFolder: Bool = false, parent: Project? = nil) -> Project {
        let project = Project(name: name, path: path, projectType: projectType, isFolder: isFolder, parent: parent)
        context.insert(project)
        
        if let parent = parent {
            project.listOrder = (parent.children?.count ?? 0) * 2 + 1
            parent.expanded = true
        } else {
            let rootProjects = fetchRootProjects()
            project.listOrder = (rootProjects.last?.listOrder ?? 0) + 2
        }
        
        try? context.save()
        return project
    }
    
    func deleteProject(_ project: Project) {
        if !project.isFolder {
            try? FileManager.default.removeItem(atPath: project.statsPath)
        }
        context.delete(project)
        try? context.save()
    }

    private func resetStuckProjects() {
        let descriptor = FetchDescriptor<Project>()
        guard let all = try? context.fetch(descriptor) else { return }
        var changed = false
        for project in all where project.isGeneratingStats {
            project.isGeneratingStats = false
            changed = true
        }
        if changed {
            try? context.save()
        }
    }
}
