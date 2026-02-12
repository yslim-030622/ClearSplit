import SwiftUI

public struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var hasBootstrapped = false

    public init() {}

    public var body: some View {
        NavigationStack {
            if !hasBootstrapped {
                ProgressView("Loading…")
            } else if appState.user != nil {
                GroupsListView(appState: appState) {
                    Task { await appState.logout() }
                }
            } else {
                LoginView(appState: appState)
            }
        }
        .task {
            guard !hasBootstrapped else { return }
            await appState.bootstrap()
            hasBootstrapped = true
        }
    }
}
