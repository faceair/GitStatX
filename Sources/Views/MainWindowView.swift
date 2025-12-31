import SwiftUI
import SwiftData

struct MainWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataController.self) private var dataController

    @State private var selectedProject: Project?
    @State private var isAddingProject = false
    @State private var isAddingFolder = false
    @State private var showingExportSheet = false
    @State private var isSelectingRepository = false

    var body: some View {
        NavigationSplitView {
            ProjectListView(
                selectedProject: $selectedProject,
                isAddingProject: $isAddingProject,
                isAddingFolder: $isAddingFolder
            )
        } detail: {
            if let project = selectedProject {
                ReportView(project: project)
                    .id(project.persistentModelID)
            } else {
                EmptyStateView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Repository", systemImage: "plus.circle") {
                        isSelectingRepository = true
                    }
                    Button("Add Folder", systemImage: "folder.badge.plus") {
                        isAddingFolder = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if let project = selectedProject, !project.isFolder {
                ToolbarItem(placement: .automatic) {
                    Button("Export", systemImage: "square.and.arrow.up") {
                        showingExportSheet = true
                    }
                    .disabled(!project.statsExists)
                }
            }
        }
        .sheet(isPresented: $isAddingProject) {
            AddProjectSheet()
        }
        .sheet(isPresented: $isAddingFolder) {
            AddFolderSheet()
        }
        .fileImporter(
            isPresented: $isSelectingRepository,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    validateAndAddRepository(url)
                }
            case .failure:
                break
            }
        }
        .fileExporter(
            isPresented: $showingExportSheet,
            document: selectedProject.map { ExportDocument(project: $0) },
            contentType: .folder,
            defaultFilename: selectedProject?.displayName ?? "GitStatX-Export"
        ) { result in
            if case .success = result {
                print("Export successful")
            }
        }
    }

    private func validateAndAddRepository(_ url: URL) {
        let path = url.path
        print("🔍 Validating repository at: \(path)")

        guard GitRepository(path: path) != nil else {
            print("❌ Not a valid Git repository: \(path)")
            return
        }

        print("✅ Valid Git repository found")
        let project = dataController.addProject(path: path, isFolder: false)
        print("📦 Project added: \(project.displayName)")

        Task { @MainActor in
            selectedProject = project
        }

        Task.detached(priority: .userInitiated) {
            await generateStats(for: project)
        }
    }

    @MainActor
    private func generateStats(for project: Project) async {
        guard !project.isFolder else { return }

        print("📊 Generating stats for project: \(project.displayName)")
        project.isGeneratingStats = true
        dataController.updateProject(project)

        do {
            let context = dataController.context
            let engine = GitStatsEngine(project: project, context: context)
            _ = try await engine.generateStats()
            print("✅ Stats generated successfully")
        } catch {
            print("❌ Error generating stats: \(error)")
        }

        project.isGeneratingStats = false
        dataController.updateProject(project)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Select a project to view statistics")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Add repositories from the toolbar to get started")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
