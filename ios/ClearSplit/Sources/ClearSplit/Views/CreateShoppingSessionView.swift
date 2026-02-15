import SwiftUI

struct CreateShoppingSessionView: View {
    @StateObject private var viewModel: CreateShoppingSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDatePickerExpanded = false
    @State private var showingError = false
    @FocusState private var isTitleFocused: Bool
    private let clearsplitBlue = Color.brandPrimary
    private let infoBlueBg = Color.infoSurface
    private let infoBlueText = Color.blue800
    
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
                Color.pageBackground
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
                    .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)

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
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color.cardInset)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isTitleFocused ? clearsplitBlue : Color.clear, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Trip title")
                    .accessibilityHint("Enter a name for this shopping trip")

                Text("Give this shopping trip a memorable name")
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textTertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Date (Optional)")
                    .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isDatePickerExpanded.toggle()
                    }
                    isTitleFocused = false
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.textSecondary)

                        Text(formattedDate)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Image(systemName: isDatePickerExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color.cardInset)
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
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderMedium, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .applyElevation(.low)
    }

    private var infoBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(infoBlueText)

            Text("Next steps: After creating this session, you'll be able to add items, upload receipts, and set who shares each item.")
                .font(ClearSplitTheme.Typography.caption)
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
                colors: [Color.pageBackground.opacity(0), Color.pageBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)

            Button(action: handleCreateSession) {
                HStack(spacing: 8) {
                    if viewModel.isCreating {
                        ProgressView()
                            .tint(.textOnBrand)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text("Create Session")
                            .font(ClearSplitTheme.Typography.bodyStrong)
                    }
                }
                .foregroundColor(.textOnBrand)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isFormValid ? clearsplitBlue : Color.interactiveDisabled)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!isFormValid || viewModel.isCreating)
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Create session")
            .accessibilityHint("Create a new shopping session with the entered title and date")
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(Color.pageBackground)
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
