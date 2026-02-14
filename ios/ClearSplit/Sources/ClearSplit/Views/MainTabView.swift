import SwiftUI

struct MainTabView: View {
    @ObservedObject private var appState: AppState
    let onLogout: () -> Void
    @State private var selectedTab: AppTab = .groups

    init(appState: AppState, onLogout: @escaping () -> Void) {
        _appState = ObservedObject(wrappedValue: appState)
        self.onLogout = onLogout
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GroupsListView(appState: appState, onLogout: onLogout)
                .tabItem {
                    Label("Groups", systemImage: "person.3.fill")
                }
                .tag(AppTab.groups)

            FriendsTabView()
                .tabItem {
                    Label("Friends", systemImage: "person.2.fill")
                }
                .tag(AppTab.friends)

            ProfileTabView(appState: appState, onLogout: onLogout)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
                .tag(AppTab.profile)
        }
        .tint(.blue600)
    }
}

private enum AppTab {
    case groups
    case friends
    case profile
}
