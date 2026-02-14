import SwiftUI

struct ProfileTabView: View {
    @ObservedObject private var appState: AppState
    let onLogout: () -> Void

    @State private var showLogoutAlert = false

    init(appState: AppState, onLogout: @escaping () -> Void) {
        _appState = ObservedObject(wrappedValue: appState)
        self.onLogout = onLogout
    }

    private var currentUser: User? {
        appState.user
    }

    private var joinedDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        if let firstGroupDate = appState.groups.map(\.createdAt).min() {
            return formatter.string(from: firstGroupDate)
        }

        return "January 2024"
    }

    private var totalGroups: Int {
        appState.groups.count
    }

    private var totalSplitAmount: Double {
        let totalCents = appState.shoppingSessionsByGroupId.values
            .flatMap { $0 }
            .reduce(0) { partial, session in
                partial + session.totalCents
            }

        return Double(totalCents) / 100
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TabLayoutMetrics.sectionSpacing) {
                    profileCard
                    statsCards
                    accountInfoCard
                    settingsCard
                    logoutButton
                }
                .padding(.horizontal, TabLayoutMetrics.horizontalPadding)
                .padding(.top, TabLayoutMetrics.topPadding)
                .padding(.bottom, TabLayoutMetrics.bottomPaddingForTabBar)
            }
            .background(Color.pageBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(Color.pageBackground.ignoresSafeArea())
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                onLogout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
    }

    private var profileCard: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue500, .blue700],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .overlay(
                    Text(currentUser?.initials ?? "?")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                )

            Text(currentUser?.displayName ?? "Unknown User")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.gray900)

            Text("Member since \(joinedDateText)")
                .font(.system(size: 14))
                .foregroundColor(.gray500)

            Button(action: {
                // Profile edit flow can be added here.
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                    Text("Edit Profile")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.blue600)
                .frame(maxWidth: 200)
                .padding(.vertical, 10)
                .background(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue600, lineWidth: 1.5)
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var statsCards: some View {
        HStack(spacing: 12) {
            ProfileStatCard(value: "\(totalGroups)", label: "Groups")
            ProfileStatCard(value: String(format: "$%.2f", totalSplitAmount), label: "Total Split")
        }
    }

    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account Information")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)

            ProfileInfoRow(
                icon: "envelope.fill",
                label: "Email",
                value: currentUser?.email ?? "-"
            )
        }
        .padding(20)
        .cardStyle()
    }

    private var settingsCard: some View {
        Button(action: {
            // Settings destination can be wired here.
        }) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray500)

                Text("Settings")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray900)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray400)
            }
            .padding(16)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private var logoutButton: some View {
        Button(action: {
            showLogoutAlert = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                Text("Log Out")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.red600)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red300, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct ProfileStatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.gray900)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.gray500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardStyle()
    }
}

struct ProfileInfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cardInset)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(.gray500)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
            }

            Spacer()
        }
    }
}
