import SwiftUI

struct CreateGroupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = CreateGroupViewModel()
    @FocusState private var isTextFieldFocused: Bool
    @State private var isButtonPressed = false
    @State private var showDiscardAlert = false
    @State private var hasAutoFocused = false

    var body: some View {
        ZStack {
            Color(hex: "F0F4F8")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                customBackButton

                ScrollView {
                    VStack(spacing: 36) {
                        logoSection
                        formCard
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(viewModel.isLoading)
        .onAppear {
            guard !hasAutoFocused else { return }
            hasAutoFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .overlay {
            if viewModel.isLoading {
                LoadingOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                triggerWarningHaptic()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("The group name you entered will be lost.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Failed to create group. Please try again.")
        }
    }

    private var customBackButton: some View {
        HStack {
            Button(action: handleBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16))
                }
                .foregroundColor(Color(hex: "374151"))
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var logoSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "3B82F6"), Color(hex: "2563EB")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color(hex: "2563EB").opacity(0.15), radius: 12, x: 0, y: 4)

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                    }
                }
            }

            Text("Create New Group")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "111827"))
                .tracking(-0.5)

            Text("Start splitting expenses with your friends")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "6B7280"))
                .multilineTextAlignment(.center)
        }
    }

    private var formCard: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Group Name")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "374151"))

                TextField("e.g., Apartment 4B", text: $viewModel.groupName)
                    .font(.system(size: 16))
                    .padding(14)
                    .background(isTextFieldFocused ? Color.white : Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isTextFieldFocused ? Color(hex: "2563EB") : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit {
                        handleCreate()
                    }
                    .animation(.easeInOut(duration: 0.2), value: isTextFieldFocused)
            }

            Button {
                handleCreate()
            } label: {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.1)
                    } else {
                        Text("Create Group")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    viewModel.canCreate
                    ? LinearGradient(
                        colors: [Color(hex: "2563EB"), Color(hex: "1D4ED8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Color(hex: "D1D5DB"), Color(hex: "D1D5DB")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
                .shadow(
                    color: viewModel.canCreate ? Color(hex: "2563EB").opacity(0.2) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
                .scaleEffect(isButtonPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonPressed)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canCreate || viewModel.isLoading)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if viewModel.canCreate && !viewModel.isLoading {
                            isButtonPressed = true
                        }
                    }
                    .onEnded { _ in
                        isButtonPressed = false
                    }
            )
        }
        .padding(24)
        .frame(maxWidth: 342)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private func handleBack() {
        if viewModel.hasUnsavedText {
            showDiscardAlert = true
            return
        }
        triggerLightImpact()
        dismiss()
    }

    private func handleCreate() {
        guard viewModel.canCreate, !viewModel.isLoading else {
            if !viewModel.canCreate {
                triggerWarningHaptic()
            }
            return
        }

        isTextFieldFocused = false
        triggerMediumImpact()
        viewModel.isLoading = true
        viewModel.errorMessage = nil

        Task {
            do {
                _ = try await appState.createGroup(
                    name: viewModel.trimmedGroupName,
                    currency: viewModel.currencyCode
                )
                await MainActor.run {
                    triggerSuccessHaptic()
                    viewModel.isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    triggerErrorHaptic()
                    viewModel.errorMessage = readableErrorMessage(from: error)
                    viewModel.isLoading = false
                }
            }
        }
    }

    private func readableErrorMessage(from error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .server(_, let message):
                if let message, !message.isEmpty {
                    return message
                }
                return "Failed to create group. Please try again."
            case .unauthorized:
                return "Your session expired. Please sign in again."
            case .decoding:
                return "Unexpected server response. Please try again."
            case .network:
                return "Network error. Check your connection and try again."
            }
        }
        return "Failed to create group. Please try again."
    }

    private func triggerMediumImpact() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
    }

    private func triggerLightImpact() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }

    private func triggerSuccessHaptic() {
#if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }

    private func triggerErrorHaptic() {
#if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
    }

    private func triggerWarningHaptic() {
#if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
#endif
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                Text("Creating Group...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
}

@MainActor
private final class CreateGroupViewModel: ObservableObject {
    @Published var groupName = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    let currencyCode = "USD"

    var canCreate: Bool {
        !trimmedGroupName.isEmpty
    }

    var trimmedGroupName: String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasUnsavedText: Bool {
        !trimmedGroupName.isEmpty
    }
}

#Preview {
    CreateGroupView()
        .environmentObject(AppState())
}
