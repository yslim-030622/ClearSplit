import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if appState.user != nil {
                    GroupsListView(appState: appState) {
                        Task { await appState.logout() }
                    }
                } else if appState.isLoading {
                    ProgressView("Loading…")
                } else {
                    LoginView(appState: appState)
                }
            }
            .task {
                await appState.bootstrap()
            }
        }
    }
}
