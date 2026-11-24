import SwiftUI

struct CloneView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var remote = ""
    @State private var destination: URL?
    @State private var isCloning = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Clone Repository", systemImage: "square.and.arrow.down").font(.title2.bold())
            Form {
                TextField("Repository URL", text: $remote, prompt: Text("https://github.com/owner/project.git"))
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Destination") {
                    Button(destination.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Choose…") { chooseDestination() }
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if isCloning { ProgressView().controlSize(.small); Text("Cloning repository…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.disabled(isCloning)
                Button("Clone") { Task { await clone() } }.keyboardShortcut(.defaultAction)
                    .disabled(remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destination == nil || isCloning)
            }
        }.padding(26).frame(width: 560).disabled(isCloning)
            .interactiveDismissDisabled(isCloning)
    }
    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Clone To"
        let name = remote.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".git", with: "") ?? "Repository"
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.begin { response in if response == .OK { destination = panel.url } }
    }
    private func clone() async {
        guard let destination else { return }
        isCloning = true
        error = nil
        do {
            try await GitRepository.clone(remote: remote.trimmingCharacters(in: .whitespacesAndNewlines), to: destination)
            library.clonedRepository = destination
            dismiss()
        } catch { self.error = error.localizedDescription }
        isCloning = false
    }
}
