import SwiftData
import Foundation
import Observation

@MainActor
class DataController: Observable {
    let container: ModelContainer
    
    init() {
        do {
            let schema = Schema([Project.self, Author.self, Commit.self, File.self])
            
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = appSupport.appendingPathComponent("GitStatX")
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            let storeURL = appDirectory.appendingPathComponent("default.store")
            
            let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
            
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = appSupport.appendingPathComponent("GitStatX")
            let storeURL = appDirectory.appendingPathComponent("default.store")
            
            try? FileManager.default.removeItem(at: storeURL)
            
            do {
                let schema = Schema([Project.self, Author.self, Commit.self, File.self])
                let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
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
    
    func fetchChildren(of parent: Project) -> [Project] {
        guard let parentId = parent.parentId else { return [] }
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.parentId == parentId
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
    
    func updateProject(_ project: Project) {
        project.save()
        try? context.save()
    }
}
