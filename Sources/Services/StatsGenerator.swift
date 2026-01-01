import Foundation
import SwiftData

enum StatsGenerator {
    @discardableResult
    static func generate(
        for project: Project,
        context: ModelContext,
        forceFullRebuild: Bool = false,
        completion: ((Result<String, Error>) -> Void)? = nil
    ) -> Task<Void, Never> {
        Task(priority: .userInitiated) {
            let result: Result<String, Error>
            do {
                let engine = GitStatsEngine(project: project, context: context)
                let path = try await engine.generateStats(forceFullRebuild: forceFullRebuild)
                result = .success(path)
            } catch {
                result = .failure(error)
            }

            if let completion {
                await MainActor.run {
                    completion(result)
                }
            }
        }
    }
}
