//
//  SignUpView.swift
//  ClearSplit
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var validationError: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Account")
                .font(.title)
                .bold()
            
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                
                SecureField("Password (min 8 chars)", text: $password)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            .disabled(authManager.isLoading)
            
            Button {
                Task {
                    if validate() {
                        // Trim email before sending
                        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        await authManager.signUp(email: trimmedEmail, password: password)
                    }
                }
            } label: {
                HStack {
                    if authManager.isLoading {
                        ProgressView().tint(.white)
                    }
                    Text("Sign Up").bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(authManager.isLoading ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
        }
        .padding()
        .navigationTitle("Sign Up")
        .alert(
            "Sign Up Failed",
            isPresented: Binding(
                get: { authManager.errorMessage != nil || validationError != nil },
                set: { if !$0 { authManager.errorMessage = nil; validationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                authManager.errorMessage = nil
                validationError = nil
            }
        } message: {
            Text(validationError ?? authManager.errorMessage ?? "Unknown error")
        }
    }
    
    private func validate() -> Bool {
        // Trim whitespace
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check email is not empty
        if trimmedEmail.isEmpty {
            validationError = "Email is required"
            return false
        }
        
        // Check email format (basic validation)
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        if !emailPredicate.evaluate(with: trimmedEmail) {
            validationError = "Please enter a valid email address"
            return false
        }
        
        // Check password length
        if password.count < 8 {
            validationError = "Password must be at least 8 characters"
            return false
        }
        
        // Check passwords match
        if password != confirmPassword {
            validationError = "Passwords do not match"
            return false
        }
        
        validationError = nil
        return true
    }
}
