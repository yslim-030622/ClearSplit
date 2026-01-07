import SwiftUI

struct GroupsListView: View {
    @StateObject private var viewModel: GroupsViewModel
    let appState: AppState
    let onLogout: () -> Void

    init(appState: AppState, onLogout: @escaping () -> Void) {
        self.appState = appState
        _viewModel = StateObject(wrappedValue: GroupsViewModel(appState: appState))
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.groups.isEmpty {
                    ProgressView()
                } else if viewModel.groups.isEmpty {
                    ContentUnavailableView("No Groups", systemImage: "person.3", description: Text("Pull to refresh."))
                } else {
                    List(viewModel.groups) { group in
                        NavigationLink {
                            GroupDetailView(appState: appState, group: group)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(group.name).font(.headline)
                                Text(group.currency).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out") { onLogout() }
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("Retry") { Task { await viewModel.load() } }
                Button("Cancel", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
