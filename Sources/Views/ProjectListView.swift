import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataController.self) private var dataController
    @Query(sort: \Project.listOrder)
    var projects: [Project]

    @Binding var selectedProject: Project?
    @Binding var isAddingProject: Bool
    @Binding var isAddingFolder: Bool

    var body: some View {
        List(selection: $selectedProject) {
            ForEach(rootProjects) { project in
                ProjectRow(project: project)
                    .tag(project)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProject = project
                    }

                if project.expanded, let children = project.children, !children.isEmpty {
                    ForEach(children) { child in
                        ProjectRow(project: child)
                            .tag(child)
                            .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 8))
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProject = child
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
        .contextMenu {
            if let project = selectedProject {
                Button("Rename", systemImage: "pencil") {
                    project.isRenaming = true
                }

                if !project.isFolder {
                    Button("Regenerate Report", systemImage: "arrow.clockwise") {
                        Task {
                            await regenerateReport(for: project)
                        }
                    }
                }

                Divider()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    dataController.deleteProject(project)
                    if selectedProject?.persistentModelID == project.persistentModelID {
                        selectedProject = nil
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private var rootProjects: [Project] {
        projects.filter { $0.parent == nil }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let path = url.path.removingPercentEncoding else { return }

                DispatchQueue.main.async {
                    if GitRepository(path: path) != nil {
                        let project = dataController.addProject(path: path, isFolder: false)

                        Task {
                            await self.generateStats(for: project)
                        }
                    }
                }
            }
        }
    }

    private func generateStats(for project: Project) async {
        guard !project.isFolder else { return }

        project.isGeneratingStats = true
        dataController.updateProject(project)

        let engine = GitStatsEngine(project: project, context: modelContext)
        _ = try? await engine.generateStats()

        project.isGeneratingStats = false
        dataController.updateProject(project)
    }

    private func regenerateReport(for project: Project) async {
        guard !project.isFolder else { return }

        project.isGeneratingStats = true
        dataController.updateProject(project)

        let engine = GitStatsEngine(project: project, context: modelContext)
        _ = try? await engine.generateStats(forceFullRebuild: true)

        project.isGeneratingStats = false
        dataController.updateProject(project)
    }
}

struct ProjectRow: View {
    @Bindable var project: Project

    @State private var isEditing = false
    @State private var editingName = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.isFolder ? "folder.fill" : projectIcon)
                .foregroundStyle(project.isFolder ? .blue : .green)
                .font(.system(size: 20))

            if project.isRenaming {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onAppear {
                        editingName = project.name ?? ""
                    }
                    .onSubmit {
                        project.name = editingName.isEmpty ? nil : editingName
                        project.isRenaming = false
                    }
                    .onDisappear {
                        project.isRenaming = false
                    }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.system(size: 13, weight: .medium))

                    if !project.isFolder {
                        if project.isGeneratingStats {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let path = project.path {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var projectIcon: String {
        switch project.projectType?.lowercased() {
        case "python":
            return "chevron.left.forwardslash.chevron.right"
        case "node.js":
            return "network"
        case "php":
            return "elephant"
        case "rubyonrails":
            return "train.side.front.car"
        case "xcodeproject":
            return "hammer"
        default:
            return "doc.text"
        }
    }
}
