import SwiftUI

struct ShoppingSessionsListView: View {
    @StateObject private var viewModel: ShoppingSessionsViewModel
    @State private var showingCreateSession = false
    
    let appState: AppState
    let groupId: UUID
    let paidByMembershipId: UUID
    
    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID) {
        self.appState = appState
        self.groupId = groupId
        self.paidByMembershipId = paidByMembershipId
        _viewModel = StateObject(wrappedValue: ShoppingSessionsViewModel(appState: appState, groupId: groupId))
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.sessions.isEmpty {
                ProgressView()
            } else if viewModel.sessions.isEmpty {
                ContentUnavailableView(
                    "No Shopping Sessions",
                    systemImage: "cart",
                    description: Text("Tap + to create your first shopping session.")
                )
            } else {
                List(viewModel.sessions) { session in
                    NavigationLink {
                        ShoppingSessionDetailView(
                            appState: appState,
                            sessionId: session.id
                        )
                    } label: {
                        ShoppingSessionRow(session: session)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Shopping")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateSession = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateShoppingSessionView(
                appState: appState,
                groupId: groupId,
                paidByMembershipId: paidByMembershipId,
                onCreated: {
                    showingCreateSession = false
                    Task { await viewModel.load() }
                }
            )
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("Retry") { Task { await viewModel.load() } }
            Button("Cancel", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct ShoppingSessionRow: View {
    let session: ShoppingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)
            
            HStack {
                if let date = session.shoppingDate {
                    Text(date, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(session.formattedTotal)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if !session.items.isEmpty {
                Text("\(session.items.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

extension ShoppingSession {
    var formattedTotal: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

