import Foundation
import SwiftUI

public struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var hasBootstrapped = false

    private var isUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_MODE")
    }

    public init() {}

    public var body: some View {
        SwiftUI.Group {
            if !hasBootstrapped {
                ProgressView("Loading…")
            } else if appState.user != nil {
                MainTabView(appState: appState) {
                    Task { await appState.logout() }
                }
            } else {
                LoginView(appState: appState)
            }
        }
        .task {
            guard !hasBootstrapped else { return }
            if isUITestMode {
                // Keep UI smoke tests deterministic by forcing a logged-out state.
                await appState.logout()
                hasBootstrapped = true
                return
            }
            await appState.bootstrap()
            hasBootstrapped = true
        }
    }
}
