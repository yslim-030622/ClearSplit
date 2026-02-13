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
                // Gradient background
                LinearGradient(
                    colors: [Color.blue50, Color.gray50],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Logo Section
                    VStack(spacing: 12) {
                        // Logo Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue600)
                                .frame(width: 64, height: 64)
                                .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
                            
                            Image(systemName: "doc.text")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("ClearSplit logo")
                        
                        // App Name
                        Text("ClearSplit")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.gray900)
                            .onAppear {
                                print("✅ NEW LOGIN VIEW IS LOADING!")
                            }
                        
                        // Tagline
                        Text("\"clearly split with your friends\"")
                            .font(.system(size: 16, weight: .regular))
                            .italic()
                            .foregroundColor(.gray600)
                    }
                    
                    Spacer()
                        .frame(height: 32)
                    
                    // Form Card
                    VStack(spacing: 20) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray700)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        focusedField == .email ? Color.blue500 : Color.gray300,
                                        lineWidth: focusedField == .email ? 2 : 1
                                    )
                                
                                if focusedField == .email {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(Color.blue500.opacity(0.5), lineWidth: 3)
                                        .padding(-3)
                                }
                                
                                TextField("you@example.com", text: $viewModel.email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray900)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit {
                                        focusedField = .password
                                    }
                                    .accessibilityIdentifier("login.emailField")
                            }
                            .frame(height: 48)
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray700)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        focusedField == .password ? Color.blue500 : Color.gray300,
                                        lineWidth: focusedField == .password ? 2 : 1
                                    )
                                
                                if focusedField == .password {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(Color.blue500.opacity(0.5), lineWidth: 3)
                                        .padding(-3)
                                }
                                
                                SecureField("••••••••", text: $viewModel.password)
                                    .textContentType(.password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray900)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        if !viewModel.email.isEmpty && !viewModel.password.isEmpty {
                                            Task { await viewModel.login() }
                                        }
                                    }
                                    .accessibilityIdentifier("login.passwordField")
                            }
                            .frame(height: 48)
                        }
                        
                        // Log In Button
                        Button {
                            Task { await viewModel.login() }
                        } label: {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Log In")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                focusedField == nil && !viewModel.isLoading && !viewModel.email.isEmpty && !viewModel.password.isEmpty
                                    ? Color.blue600
                                    : Color.blue600.opacity(0.9)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
                        .opacity((viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty) ? 0.5 : 1.0)
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityIdentifier("login.submitButton")
                    }
                    .padding(24)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray200, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                    
                    Spacer()
                        .frame(height: 32)
                    
                    // Sign Up Section
                    VStack(spacing: 12) {
                        Text("Don't have an account?")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray600)
                        
                        Button {
                            showSignUp = true
                        } label: {
                            Text("Create Account")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.gray900)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray200, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(viewModel.isLoading)
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityIdentifier("login.createAccountButton")
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 384)
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
}
