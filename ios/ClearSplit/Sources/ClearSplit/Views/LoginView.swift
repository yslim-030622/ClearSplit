import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    @State private var showSignUp = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    Spacer()

                    headerSection

                    Spacer()
                        .frame(height: 40)

                    formCard

                    Spacer()
                        .frame(height: 24)

                    signUpSection

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 384)
                .frame(maxWidth: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSignUp) {
                SignUpView(appState: viewModel.appState)
            }
            .alert("Error", isPresented: $viewModel.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "Unknown error")
            }
        }
    }

    private var canSubmit: Bool {
        !viewModel.isLoading && !viewModel.email.isEmpty && !viewModel.password.isEmpty
    }

    private var headerSection: some View {
        VStack(spacing: 20) {
            // Eyes
            HStack(spacing: 16) {
                eyeShape(colors: [Color.blue500, Color.blue600], rotation: -10)
                eyeShape(colors: [Color.blue600, Color.blue800], rotation: 10)
            }
            .shadow(color: Color.blue600.opacity(0.3), radius: 12, y: 4)

            VStack(spacing: 8) {
                // Curved "ClearSplit" smile
                smileyText

                Text("Split expenses, not friendships")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.textTertiary)
            }
        }
        .accessibilityLabel("ClearSplit logo")
    }

    private func eyeShape(colors: [Color], rotation: Double) -> some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 38)

            // Gleam highlight
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 8, height: 8)
                .offset(x: -4, y: -8)
        }
        .rotationEffect(.degrees(rotation))
    }

    private var smileyText: some View {
        let characters = Array("ClearSplit")

        return ZStack {
            ForEach(Array(0..<characters.count), id: \.self) { i in
                smileyCharacter(characters[i], index: i, total: characters.count)
            }
        }
        .frame(height: 60)
    }

    private func smileyCharacter(_ char: Character, index: Int, total: Int) -> some View {
        let radius: Double = 400
        let totalAngle: Double = 30
        let angle = -totalAngle / 2.0 + Double(index) * totalAngle / Double(total - 1)
        let rad = angle * .pi / 180

        return Text(String(char))
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundColor(index >= 5 ? .brandPrimary : .textPrimary)
            .rotationEffect(.degrees(-angle))
            .offset(
                x: radius * sin(rad),
                y: radius * (cos(rad) - 1)
            )
    }

    private var formCard: some View {
        VStack(spacing: 20) {
            labeledInput(title: "Email", isFocused: focusedField == .email) {
                TextField("you@example.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .accessibilityIdentifier("login.emailField")
            }

            labeledInput(title: "Password", isFocused: focusedField == .password) {
                SecureField("••••••••", text: $viewModel.password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit {
                        guard canSubmit else { return }
                        Task { await viewModel.login() }
                    }
                    .accessibilityIdentifier("login.passwordField")
            }

            Button {
                Task { await viewModel.login() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Log In")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(isEnabled: canSubmit))
            .disabled(!canSubmit)
            .accessibilityIdentifier("login.submitButton")
        }
        .padding(24)
        .cardStyle()
    }

    private var signUpSection: some View {
        VStack(spacing: 16) {
            // Divider with text
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.borderLight)
                    .frame(height: 0.5)

                Text("or")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.textMuted)

                Rectangle()
                    .fill(Color.borderLight)
                    .frame(height: 0.5)
            }

            Button {
                showSignUp = true
            } label: {
                Text("Create Account")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionButtonStyle(isEnabled: !viewModel.isLoading))
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("login.createAccountButton")
        }
    }

    private func labeledInput<Content: View>(
        title: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                .foregroundColor(.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.cardBackground : Color.cardInset)

                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFocused ? Color.brandPrimary : Color.borderLight,
                        lineWidth: isFocused ? 2 : 1
                    )

                if isFocused {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.brandPrimary.opacity(0.20), lineWidth: 3)
                        .padding(-3)
                }

                content()
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .frame(height: 48)
        }
    }
}