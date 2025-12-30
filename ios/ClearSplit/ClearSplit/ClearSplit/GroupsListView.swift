//
//  GroupsListView.swift
//  ClearSplit
//

import SwiftUI

struct GroupsListView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = GroupsViewModel()
    @State private var showCreateGroup: Bool = false
    
    var body: some View {
        SwiftUI.Group {
            if viewModel.isLoading && viewModel.groups.isEmpty {
                ProgressView("Loading groups...")
            } else if viewModel.groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.3")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No groups yet")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("Tap + to create your first group")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                List(viewModel.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.headline)
                        Text(group.currency)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .refreshable {
                    await viewModel.load()
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Log Out") {
                    authManager.logOut()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateGroup = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupView(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .task {
            await viewModel.load()
        }
    }
}
