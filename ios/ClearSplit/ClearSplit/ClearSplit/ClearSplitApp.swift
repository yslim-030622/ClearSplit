import SwiftUI
import ClearSplitCore
import UIKit

@main
struct ClearSplitApp: App {
    @StateObject private var appState = AppState()

    init() {
        if ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_ANIMATIONS") {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
