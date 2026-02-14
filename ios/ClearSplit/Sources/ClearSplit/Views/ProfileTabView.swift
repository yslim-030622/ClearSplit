import SwiftUI

struct ProfileTabView: View {
    @ObservedObject private var appState: AppState
    let onLogout: () -> Void

    init(appState: AppState, onLogout: @escaping () -> Void) {
        _appState = ObservedObject(wrappedValue: appState)
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.pageBackground
                    .ignoresSafeArea()

                if let user = appState.user {
                    VStack(spacing: 16) {
                        Text(user.initials)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.blue600)
                            .clipShape(Circle())

                        VStack(spacing: 4) {
                            Text(user.displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.gray900)

                            Text("@\(user.username)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray600)

                            Text(user.email)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray600)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .padding(.horizontal, 24)
                    .cardStyle()
                    .padding(.horizontal, 16)
                } else {
                    Text("No active session")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray600)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log Out", role: .destructive, action: onLogout)
                }
            }
        }
    }
}
