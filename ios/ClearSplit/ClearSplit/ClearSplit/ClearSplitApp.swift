//
//  ClearSplitApp.swift
//  ClearSplit
//

import SwiftUI

@main
struct ClearSplitApp: App {
    @StateObject private var authManager = AuthManager()
    
    init() {
        #if DEBUG
        print("🚀 ClearSplit launching...")
        print("📡 API Base URL: \(APIConfig.baseURL.absoluteString)")
        print("💡 Note: Simulator can use localhost. Physical devices must use Mac LAN IP.")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
        }
    }
}
