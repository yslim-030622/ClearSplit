//
//  LoginView.swift
//  ClearSplit
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email: String = ""
    @State private var password: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("ClearSplit")
                .font(.largeTitle)
                .bold()
            
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            .disabled(authManager.isLoading)
            
            Button {
                Task {
                    // Trim email before sending
                    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    await authManager.logIn(email: trimmedEmail, password: password)
                }
            } label: {
                HStack {
                    if authManager.isLoading {
                        ProgressView().tint(.white)
                    }
                    Text("Log In").bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(authManager.isLoading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
            
            NavigationLink("Create account") {
                SignUpView()
            }
            .padding(.top, 8)
        }
        .padding()
        .navigationTitle("Login")
        .alert(
            "Login Failed",
            isPresented: Binding(
                get: { authManager.errorMessage != nil },
                set: { if !$0 { authManager.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                authManager.errorMessage = nil
            }
        } message: {
            Text(authManager.errorMessage ?? "Unknown error")
        }
    }
}
