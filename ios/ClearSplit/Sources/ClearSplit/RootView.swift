import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            if appState.user != nil {
                GroupsListView(appState: appState) {
                    Task { await appState.logout() }
                }
                .task {
                    await appState.bootstrap()
                }
            } else if appState.isLoading {
                ProgressView("Loading…")
                    .task {
                        await appState.bootstrap()
                    }
            } else {
                LoginView(appState: appState)
                    .task {
                        await appState.bootstrap()
                    }
            }
        }
    }
}
