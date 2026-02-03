import SwiftUI

// Custom button style for press feedback
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ShoppingSessionsListView: View {
    @StateObject private var viewModel: ShoppingSessionsViewModel
    @State private var showingCreateSession = false
    @State private var showingError = false
    
    let appState: AppState
    let groupId: UUID
    let paidByMembershipId: UUID
    
    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID) {
        self.appState = appState
        self.groupId = groupId
        self.paidByMembershipId = paidByMembershipId
        _viewModel = StateObject(wrappedValue: ShoppingSessionsViewModel(appState: appState, groupId: groupId))
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background
            Color(hex: "F9FAFB")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.isLoading && viewModel.sessions.isEmpty {
                        ProgressView()
                            .padding(.top, 100)
                    } else if viewModel.sessions.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "cart.badge.plus")
                                .font(.system(size: 64, weight: .light))
                                .foregroundColor(Color(hex: "9CA3AF"))
                            
                            Text("No Shopping Sessions Yet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(hex: "111827"))
                            
                            Text("Create your first shopping session to start")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.top, 100)
                    } else {
                        // Session cards
                        ForEach(viewModel.sessions) { session in
                            NavigationLink {
                                ShoppingSessionDetailView(
                                    appState: appState,
                                    sessionId: session.id
                                )
                            } label: {
                                ShoppingSessionCard(session: session)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
            
            // Floating Add button
            Button(action: { showingCreateSession = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color(hex: "2563EB"))
                    .clipShape(Circle())
                    .shadow(color: Color(hex: "2563EB").opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            
            // Error Overlay
            if showingError && viewModel.errorMessage != nil {
                ErrorOverlay(
                    message: viewModel.errorMessage ?? "Failed to load shopping sessions.",
                    onCancel: {
                        showingError = false
                        viewModel.errorMessage = nil
                    },
                    onRetry: {
                        showingError = false
                        Task {
                            await viewModel.load()
                        }
                    }
                )
            }
        }
        .navigationTitle("Shopping Sessions")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.errorMessage) { oldValue, newValue in
            showingError = newValue != nil
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateShoppingSessionView(
                appState: appState,
                groupId: groupId,
                paidByMembershipId: paidByMembershipId,
                onCreated: {
                    showingCreateSession = false
                    Task { await viewModel.load() }
                }
            )
        }
    }
}

// MARK: - Error Overlay

struct ErrorOverlay: View {
    let message: String
    let onCancel: () -> Void
    let onRetry: () -> Void
    
    var body: some View {
        ZStack {
            // Backdrop - translucent
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            
            // Error Card - translucent white
            VStack(spacing: 16) {
                // Title
                Text("Error")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.gray900)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Message
                Text(message)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray900)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Buttons
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.gray900)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.gray200)
                            .cornerRadius(12)
                    }
                    
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.gray900)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.gray200)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.9))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            .frame(maxWidth: 320)
        }
    }
}

struct ShoppingSessionCard: View {
    let session: ShoppingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and amount
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "111827"))
                        .lineLimit(2)
                    
                    if let date = session.shoppingDate {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "6B7280"))
                            Text(date, style: .date)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.formattedTotal)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color(hex: "111827"))
                    
                    if !session.items.isEmpty {
                        Text("\(session.items.count) item\(session.items.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                    }
                }
            }
            .padding(20)
            
            // Footer with participants count (if any)
            if !session.participants.isEmpty {
                Divider()
                    .padding(.horizontal, 20)
                
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "6B7280"))
                    Text("\(session.participants.count) participant\(session.participants.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(hex: "6B7280"))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

extension ShoppingSession {
    var formattedTotal: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

