import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            EditorSettings().tabItem { Label("Editor", systemImage: "textformat.size") }
            WorkspaceSettings().tabItem { Label("Workspace", systemImage: "sidebar.left") }
            IntelligenceSettings().tabItem { Label("Intelligence", systemImage: "sparkles") }
        }.frame(width: 620, height: 600)
    }
}

struct AppearanceSettings: View {
    @Environment(Preferences.self) private var preferences
    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Appearance", selection: $preferences.appearance) {
                    Text("Automatic").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
                LabeledContent("Accent colour") { ColorChoices(selection: $preferences.accent) }
                Toggle("Use each project’s accent colour", isOn: $preferences.layout.useProjectAccent)
            }
            Section("Typography & Spacing") {
                Picker("Interface font", selection: $preferences.layout.interfaceFont) {
                    Text("System").tag("system")
                    Text("Rounded").tag("rounded")
                    Text("Serif").tag("serif")
                    Text("Monospaced").tag("monospaced")
                }
                Stepper("Text size: \(Int(preferences.layout.interfaceSize)) pt", value: $preferences.layout.interfaceSize, in: 11...18, step: 1)
                Picker("Density", selection: $preferences.layout.density) {
                    Text("Compact").tag("compact")
                    Text("Standard").tag("standard")
                    Text("Relaxed").tag("relaxed")
                }.pickerStyle(.segmented)
                Text("A little clarity for every commit.")
                    .font(.system(size: preferences.layout.interfaceSize, design: preferences.layout.fontDesign))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
            }
            Section {
                Toggle("Animate project icons", isOn: $preferences.layout.animateIcons)
                Button("Reset Appearance & Workspace") { preferences.resetAppearance() }
            }
        }.formStyle(.grouped)
    }
}

struct IntelligenceSettings: View {
    @Environment(Preferences.self) private var preferences
    @State private var key = ""
    @State private var keySaved = false
    @State private var keyError: String?
    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Write with", selection: $preferences.provider) {
                    ForEach(AIProvider.allCases) { provider in Text(provider.name).tag(provider) }
                }
                if preferences.provider == .apple {
                    if let reason = CommitWriter.availability {
                        Label(reason, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Label("Ready on this Mac", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } else {
                    TextField("Model", text: $preferences.model)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    HStack {
                        SecureField("Key", text: $key).textFieldStyle(.roundedBorder)
                            .onChange(of: key) { keySaved = false }
                        Button(keySaved ? "Saved" : "Save") {
                            do { try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: preferences.provider); keySaved = true; keyError = nil }
                            catch { keyError = error.localizedDescription }
                        }
                    }
                    if let keyError { Text(keyError).font(.caption).foregroundStyle(.red) }
                }
            } footer: {
                Text(preferences.provider == .apple ? "Commit messages are written on your Mac. Your code stays on your device." : "When you choose Write, selected changes are sent to \(preferences.provider.name). Keys are stored securely in macOS Keychain.")
            }
            Section {
                TextEditor(text: $preferences.instruction).font(.body).frame(height: 80)
                    .accessibilityLabel("Commit writing instructions")
            } header: { Text("Commit Style") } footer: { Text("Tell Silver how you like your summaries and descriptions written.") }
        }
        .formStyle(.grouped)
        .task(id: preferences.provider) { key = KeychainStore.read(preferences.provider); keySaved = false; keyError = nil }
    }
}
