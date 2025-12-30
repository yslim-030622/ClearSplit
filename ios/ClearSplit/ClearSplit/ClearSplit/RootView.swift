//
//  RootView.swift
//  ClearSplit
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if authManager.isLoading {
                    ProgressView("Loading...")
                } else if authManager.isAuthenticated {
                    GroupsListView()
                } else {
                    LoginView()
                }
            }
            .task {
                await authManager.bootstrap()
            }
        }
    }
}

