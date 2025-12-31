import SwiftUI
import SwiftData
import AppKit

@main
struct GitStatXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var dataController = DataController()
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(dataController)
                .environment(\.modelContext, dataController.context)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }
}
