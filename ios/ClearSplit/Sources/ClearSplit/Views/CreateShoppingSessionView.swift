import SwiftUI

struct CreateShoppingSessionView: View {
    @StateObject private var viewModel: CreateShoppingSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDatePickerExpanded = false
    @State private var showingError = false
    @FocusState private var isTitleFocused: Bool
    private let clearsplitBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    private let infoBlueBg = Color(red: 0.239, green: 0.596, blue: 0.953).opacity(0.1)
    private let infoBlueText = Color(red: 0.153, green: 0.380, blue: 0.753)
    
    let onCreated: () -> Void
    
    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID, onCreated: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: CreateShoppingSessionViewModel(
            appState: appState,
            groupId: groupId,
            paidByMembershipId: paidByMembershipId
        ))
        self.onCreated = onCreated
    }
    
    private var trimmedTitle: String {
        viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= 100
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: viewModel.shoppingDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gray50
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        formCard
                        infoBox
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("New Shopping Session")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                        }
                        .foregroundColor(clearsplitBlue)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                createButton
            }
            .disabled(viewModel.isCreating)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTitleFocused = true
                }
                // Keep backend payload behavior aligned with this screen (always uses selected date).
                viewModel.useDate = true
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "Failed to create shopping session.")
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trip Title")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray700)

                TextField("e.g., Weekly Groceries, Costco Run", text: $viewModel.title)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if isFormValid && !viewModel.isCreating {
                            handleCreateSession()
                        }
                    }
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray900)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color(UIColor.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isTitleFocused ? clearsplitBlue : Color.clear, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Trip title")
                    .accessibilityHint("Enter a name for this shopping trip")

                Text("Give this shopping trip a memorable name")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray500)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Date (Optional)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray700)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isDatePickerExpanded.toggle()
                    }
                    isTitleFocused = false
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.gray600)

                        Text(formattedDate)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.gray900)

                        Spacer()

                        Image(systemName: isDatePickerExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray600)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color(UIColor.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDatePickerExpanded ? clearsplitBlue : Color.clear, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Session date")
                .accessibilityHint("Choose a date for this shopping session")

                if isDatePickerExpanded {
                    DatePicker(
                        "",
                        selection: $viewModel.shoppingDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Text("Defaults to today if not set")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var infoBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(infoBlueText)

            Text("Next steps: After creating this session, you'll be able to add items, upload receipts, and set who shares each item.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(infoBlueText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(infoBlueBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var createButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.gray50.opacity(0), Color.gray50],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)

            Button(action: handleCreateSession) {
                HStack(spacing: 8) {
                    if viewModel.isCreating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text("Create Session")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isFormValid ? clearsplitBlue : Color.gray400)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!isFormValid || viewModel.isCreating)
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Create session")
            .accessibilityHint("Create a new shopping session with the entered title and date")
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(Color.gray50)
        }
    }

    private func handleCreateSession() {
        guard isFormValid else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isTitleFocused = false
        viewModel.useDate = true

        Task {
            let session = await viewModel.createSession()
            if session != nil {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCreated()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showingError = true
            }
        }
    }
}
