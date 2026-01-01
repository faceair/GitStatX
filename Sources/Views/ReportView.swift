import SwiftUI
import SwiftData
import WebKit

struct ReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @State private var isGeneratingStats = false
    @State private var statsPath: String?
    @State private var error: String?
    @State private var progressStage: String?
    @State private var progressDetail: String?
    
    var body: some View {
        ZStack {
            if let path = statsPath {
                WebReportView(statsPath: path)
            } else if isGeneratingStats {
                GeneratingStatsView(stage: progressStage, detail: progressDetail)
            } else if let err = error {
                ErrorView(error: err) {
                    Task {
                        await generateStats()
                    }
                }
            } else {
                EmptyReportView {
                    Task {
                        await generateStats()
                    }
                }
            }
        }
        .onAppear {
            isGeneratingStats = project.isGeneratingStats
            progressStage = project.progressStage
            progressDetail = project.progressDetail
            loadCachedReportIfAvailable()
            Task { await ensureFreshReport() }
        }
        .onChange(of: project.isGeneratingStats) { _, generating in
            isGeneratingStats = generating
            if !generating {
                refreshReportView()
            }
        }
        .onChange(of: project.progressStage) { _, stage in
            progressStage = stage
        }
        .onChange(of: project.progressDetail) { _, detail in
            progressDetail = detail
        }
        .onChange(of: project.lastGeneratedCommit) { _, _ in
            refreshReportView()
        }
    }
    
    private func generateStats() async {
        isGeneratingStats = statsPath == nil
        error = nil
        
        StatsGenerator.generate(
            for: project,
            context: modelContext,
            completion: { result in
            switch result {
            case .success(let path):
                statsPath = path
            case .failure(let generationError):
                error = generationError.localizedDescription
            }
            isGeneratingStats = false
        })
    }

    private func refreshReportView() {
        guard project.statsExists else {
            statsPath = nil
            return
        }
        let path = project.statsPath
        if statsPath == path {
            statsPath = nil
            DispatchQueue.main.async {
                statsPath = path
            }
        } else {
            statsPath = path
        }
    }

    private func loadCachedReportIfAvailable() {
        if project.statsExists {
            statsPath = project.statsPath
            isGeneratingStats = false
        }
    }

    private func ensureFreshReport() async {
        guard !isReportUpToDate() else { return }
        await generateStats()
    }

    private func isReportUpToDate() -> Bool {
        guard project.statsExists, let repoPath = project.path, let repository = GitRepository(path: repoPath), let head = repository.currentCommitHash else {
            return false
        }

        if let cache = loadStatsCache(), cache.lastCommit == head {
            return true
        }

        if let last = project.lastGeneratedCommit, last == head {
            return true
        }

        return false
    }

    private func loadStatsCache() -> StatsCache? {
        let cacheURL = URL(fileURLWithPath: project.statsPath).appendingPathComponent("stats_cache.json")
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StatsCache.self, from: data)
        } catch {
            return nil
        }
    }
}

struct WebReportView: NSViewRepresentable {
    let statsPath: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator as? WKUIDelegate
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        
        let url = URL(fileURLWithPath: statsPath).appendingPathComponent("index.html")
        webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: statsPath))
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let url = URL(fileURLWithPath: statsPath).appendingPathComponent("index.html")
        if nsView.url != url {
            nsView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: statsPath))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        }
    }
}

struct GeneratingStatsView: View {
    let stage: String?
    let detail: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(stage ?? "Generating statistics...")
                .font(.headline)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("This may take a while for large repositories")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyReportView: View {
    let onGenerate: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Statistics Available")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Generate git statistics to view the report")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: onGenerate) {
                Label("Generate Statistics", systemImage: "play.fill")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let error: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            
            Text("Error Generating Statistics")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
