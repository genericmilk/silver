import SwiftUI

struct BranchesView: View {
    @Bindable var store: RepositoryStore
    @State private var search = ""
    private var branches: [GitBranch] {
        (store.snapshot?.branches ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Branches").font(.title2.bold())
                Spacer()
                TextField("Search branches", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                Button { store.showNewBranch = true } label: { Label("New Branch", systemImage: "plus") }.disabled(store.isBusy)
            }.padding(22)
            Divider()
            if branches.isEmpty {
                ContentUnavailableView("No Branches", systemImage: "arrow.triangle.branch", description: Text("Create your first commit to begin building branches."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    branchSection("Local", branches: branches.filter { !$0.remote })
                    branchSection("Remotes", branches: branches.filter(\.remote))
                }.listStyle(.inset)
            }
        }
    }
    @ViewBuilder private func branchSection(_ title: String, branches: [GitBranch]) -> some View {
        if !branches.isEmpty {
            Section(title) {
                ForEach(branches) { branch in
                    HStack(spacing: 12) {
                        Image(systemName: branch.remote ? "network" : "arrow.triangle.branch").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(branch.name).fontWeight(branch.current ? .semibold : .regular)
                            if !branch.upstream.isEmpty { Text(branch.upstream).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if branch.current { Label("Current", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
                        else if !branch.remote {
                            Button("Switch") { Task { await store.switchBranch(branch) } }.disabled(store.isBusy)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }
    }
}
