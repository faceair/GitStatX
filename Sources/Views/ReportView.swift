import SwiftUI
import SwiftData
import WebKit

struct ReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @State private var isGeneratingStats = false
    @State private var statsPath: String?
    @State private var error: String?
    @State private var processedCommits: Int = 0
    @State private var totalCommits: Int = 0
    @State private var stage: GitStatsEngine.ProgressUpdate.Stage = .scanning
    
    var body: some View {
        ZStack {
            if isGeneratingStats {
                GeneratingStatsView(processed: processedCommits, total: totalCommits, stage: stage)
            } else if let path = statsPath {
                WebReportView(statsPath: path)
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
            syncProgressFromProject()
            if statsPath == nil && !isGeneratingStats && error == nil {
                Task {
                    await generateStats()
                }
            }
        }
    }
    
    private func generateStats() async {
        isGeneratingStats = true
        error = nil
        syncProgressFromProject()
        
        StatsGenerator.generate(
            for: project,
            context: modelContext,
            progress: { update in
                Task { @MainActor in
                    processedCommits = update.processed
                    totalCommits = update.total
                    stage = update.stage
                }
            },
            completion: { result in
            switch result {
            case .success(let path):
                statsPath = path
                stage = .processing
            case .failure(let generationError):
                error = generationError.localizedDescription
            }
            isGeneratingStats = false
        })
    }

    private func syncProgressFromProject() {
        processedCommits = project.progressProcessed
        totalCommits = project.progressTotal
        stage = stageFromProject()
    }

    private func stageFromProject() -> GitStatsEngine.ProgressUpdate.Stage {
        switch project.progressStage {
        case "processing":
            return .processing
        case "scanning":
            return .scanning
        default:
            return .scanning
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
    let processed: Int
    let total: Int
    let stage: GitStatsEngine.ProgressUpdate.Stage

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text(stageText)
                .font(.headline)
            Text("This may take a while for large repositories")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if total > 0 {
                ProgressView(value: Double(processed), total: Double(total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 320)
                Text("\(processed)/\(total) commits processed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stageText: String {
        switch stage {
        case .scanning:
            return "Analyzing Git Repository..."
        case .processing:
            return "Processing commit diffs..."
        }
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
