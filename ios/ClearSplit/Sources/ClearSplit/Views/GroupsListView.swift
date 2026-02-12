import SwiftUI

struct GroupsListView: View {
    @StateObject private var viewModel: GroupsViewModel
    let appState: AppState
    let onLogout: () -> Void
    @State private var showCreateGroup = false
    @State private var showLogoutAlert = false

    init(appState: AppState, onLogout: @escaping () -> Void) {
        self.appState = appState
        _viewModel = StateObject(wrappedValue: GroupsViewModel(appState: appState))
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                Color(hex: "F9FAFB")
                    .ignoresSafeArea()
                
                // Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("My Groups")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(Color(hex: "111827"))
                                .tracking(-0.5)
                            
                            Spacer()
                            
                            // Logout button (top right)
                            Button(action: { showLogoutAlert = true }) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(Color(hex: "2563EB"))
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Log out")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 47 + 8) // Safe area + spacing
                        
                        // Group Cards
                        if viewModel.isLoading && viewModel.groups.isEmpty {
                            // Loading skeleton
                            VStack(spacing: 12) {
                                ForEach(0..<3) { _ in
                                    GroupCardSkeleton()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        } else if viewModel.groups.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "person.3")
                                    .font(.system(size: 64))
                                    .foregroundColor(Color(hex: "D1D5DB"))
                                
                                Text("No groups yet")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(hex: "4B5563"))
                                
                                Text("Create a group to start splitting expenses")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color(hex: "6B7280"))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(viewModel.groups) { group in
                                    GroupCard(group: group, appState: appState)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 100) // Space for button
                        }
                    }
                }
                .refreshable {
                    await viewModel.load()
                }
                
                // Bottom Button
                Button(action: { showCreateGroup = true }) {
                    Text("Create New Group")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(hex: "2563EB"))
                        .cornerRadius(12)
                        .shadow(color: Color(hex: "2563EB").opacity(0.2), radius: 8, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 34 + 16) // Safe area + margin
                .accessibilityLabel("Create new group")
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView()
                    .environmentObject(appState)
            }
        }
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                onLogout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .task {
            await viewModel.load()
        }
        .navigationDestination(for: CSGroup.self) { group in
            GroupDetailView(appState: appState, group: group)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("Retry") { Task { await viewModel.load() } }
            Button("Cancel", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct GroupCard: View {
    let group: CSGroup
    let appState: AppState
    @State private var isPressed = false
    
    // TODO: These should come from the API or be calculated
    // For now, using placeholder values
    private var memberCount: Int {
        // This should be fetched from the API or calculated
        // For now, return a placeholder
        return 4 // Placeholder
    }
    
    private var userBalance: Decimal {
        // This should come from the API or be calculated from settlements
        // For now, return 0 (settled)
        return 0 // Placeholder - will need to fetch from balance/settlement API
    }
    
    private var isSettled: Bool {
        userBalance == 0
    }
    
    var body: some View {
        NavigationLink(value: group) {
            HStack(spacing: 0) {
                // Left: Group info
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "111827"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                            .renderingMode(.template)
                        
                        Text("\(memberCount) \(memberCount == 1 ? "member" : "members")")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "4B5563"))
                    }
                }
                
                Spacer()
                
                // Right: Balance
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !isSettled {
                            Text("Your balance")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                        }
                        
                        if isSettled {
                            Text("All settled up")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                        } else {
                            Text(balanceText)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(balanceColor)
                        }
                    }
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
            }
            .padding(16)
            .frame(height: 72)
            .background(isPressed ? Color(hex: "F9FAFB") : .white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
            )
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
            .scaleEffect(isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
    
    private var balanceText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = group.currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        
        let amount = abs(userBalance)
        let formatted = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00"
        
        return userBalance > 0 ? "+\(formatted)" : formatted
    }
    
    private var balanceColor: Color {
        userBalance > 0 ? Color(hex: "16A34A") : Color(hex: "DC2626")
    }
}

struct GroupCardSkeleton: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 120, height: 17)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 80, height: 14)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 70, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 60, height: 17)
            }
        }
        .padding(16)
        .frame(height: 72)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

