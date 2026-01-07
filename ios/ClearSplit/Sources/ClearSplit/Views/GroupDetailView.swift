import SwiftUI

struct GroupDetailView: View {
    let appState: AppState
    let group: CSGroup
    
    var body: some View {
        List {
            Section("Group Info") {
                LabeledContent("Name", value: group.name)
                LabeledContent("Currency", value: group.currency)
            }
            
            Section {
                if let membershipId = group.userMembershipId {
                    NavigationLink {
                        ShoppingSessionsListView(
                            appState: appState,
                            groupId: group.id,
                            paidByMembershipId: membershipId
                        )
                    } label: {
                        Label("Shopping Sessions", systemImage: "cart.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                } else {
                    Label("Shopping Sessions (Unavailable)", systemImage: "cart")
                        .foregroundColor(.secondary)
                }
                
                NavigationLink {
                    Text("🚧 Coming Soon: Expenses")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } label: {
                    Label("Expenses", systemImage: "dollarsign.circle")
                        .font(.headline)
                }
            } header: {
                Text("Features")
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

