import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    
    let statsPath: String
    
    init(project: Project) {
        self.statsPath = project.statsPath
    }
    
    init(configuration: ReadConfiguration) throws {
        throw ExportError.notSupported
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: statsPath) else {
            throw ExportError.noStats
        }
        
        let wrapper = try FileWrapper(url: URL(fileURLWithPath: statsPath))
        return wrapper
    }
}

enum ExportError: Error {
    case notSupported
    case noStats
}
