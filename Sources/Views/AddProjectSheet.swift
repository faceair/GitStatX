import SwiftUI

struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataController.self) private var dataController
    
    @State private var selectedURL: URL?
    @State private var isSelecting = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Git Repository")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select a folder containing a Git repository")
                .font(.body)
                .foregroundStyle(.secondary)
            
            if let url = selectedURL {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(url.path)
                        .font(.body)
                        .lineLimit(2)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                Button("Browse...") {
                    isSelecting = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(30)
        .frame(width: 500)
        .fileImporter(
            isPresented: $isSelecting,
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
    }
    
    private func validateAndAddRepository(_ url: URL) {
        let path = url.path
        print("🔍 Validating repository at: \(path)")
        
        guard GitRepository(path: path) != nil else {
            print("❌ Not a valid Git repository: \(path)")
            selectedURL = nil
            return
        }
        
        print("✅ Valid Git repository found")
        let project = dataController.addProject(path: path, isFolder: false)
        print("📦 Project added: \(project.displayName)")
        
        Task { @MainActor in
            dismiss()
        }
        
        StatsGenerator.generate(for: project, context: dataController.context, completion: { result in
            if case let .failure(error) = result {
                print("❌ Error generating stats: \(error)")
            } else {
                print("✅ Stats generated successfully")
            }
        })
    }
}

struct AddFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataController.self) private var dataController
    
    @State private var folderName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Folder")
                .font(.title2)
                .fontWeight(.semibold)
            
            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            
            HStack(spacing: 12) {
                Button("Add") {
                    if !folderName.isEmpty {
                        _ = dataController.addProject(name: folderName, isFolder: true)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(folderName.isEmpty)
                .keyboardShortcut(.defaultAction)
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(30)
        .frame(width: 400)
        .onAppear {
            folderName = "New Folder"
        }
    }
}
