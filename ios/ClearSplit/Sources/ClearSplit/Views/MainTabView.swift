import SwiftUI

#if os(iOS)
import UIKit
#endif

enum MainTab: String, CaseIterable {
    case groups = "Groups"
    case friends = "Friends"
    case profile = "Profile"

    var icon: String {
        switch self {
        case .groups: return "person.2.fill"
        case .friends: return "person.badge.plus.fill"
        case .profile: return "person.circle.fill"
        }
    }

    var iconUnselected: String {
        switch self {
        case .groups: return "person.2"
        case .friends: return "person.badge.plus"
        case .profile: return "person.circle"
        }
    }
}

struct MainTabView: View {
    @ObservedObject private var appState: AppState
    let onLogout: () -> Void

    @State private var selectedTab: MainTab = .groups

    init(appState: AppState, onLogout: @escaping () -> Void) {
        _appState = ObservedObject(wrappedValue: appState)
        self.onLogout = onLogout
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                tabView(.groups) {
                    GroupsListView(appState: appState)
                }

                tabView(.friends) {
                    FriendsTabView(appState: appState)
                }

                tabView(.profile) {
                    ProfileTabView(appState: appState, onLogout: onLogout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 64)

            MainTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(
            Color.pageBackground
                .ignoresSafeArea()
        )
    }

    private func tabView<Content: View>(_ tab: MainTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }
}

struct MainTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    onTap: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                        triggerSelectionFeedback()
                    }
                )
            }
        }
        .frame(height: 64)
        .background(Color.cardBackground)
        .overlay(
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 0.5),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: -4)
        .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: -1)
    }

    private func triggerSelectionFeedback() {
#if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
#endif
    }
}

struct TabBarButton: View {
    let tab: MainTab
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.icon : tab.iconUnselected)
                    .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color.brandPrimary : Color.textMuted)

                Text(tab.rawValue)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Color.brandPrimary : Color.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(isPressed ? 0.95 : 1)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(isSelected ? Color.brandPrimary : Color.clear)
                    .frame(width: 24, height: 3)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}
