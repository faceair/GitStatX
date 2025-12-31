import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 500, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("GitStatX Settings")
                    .font(.headline)
                
                Text("Version 2.0")
                    .foregroundStyle(.secondary)
            }
            
            Section {
                HStack {
                    Text("Theme")
                    Spacer()
                    Picker("Theme", selection: .constant("System")) {
                        Text("System").tag("System")
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
