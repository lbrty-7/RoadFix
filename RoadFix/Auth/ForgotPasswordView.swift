//
//  ForgotPasswordView.swift
//  RoadFix
//

import SwiftUI

/// Sends a Firebase password reset email. Opened from LoginView.
struct ForgotPasswordView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var isValidEmail: Bool {
        email.contains("@") && email.contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("We'll email you a link to choose a new password.")
                }

                if sent {
                    Section {
                        Label("If an account exists for \(email), a reset link is on its way. Check your inbox and spam folder.", systemImage: "envelope.badge")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        send()
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text(sent ? "Send Again" : "Send Reset Link")
                        }
                    }
                    .disabled(!isValidEmail || isSending)
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func send() {
        isSending = true
        errorMessage = nil
        let address = email.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await authViewModel.sendPasswordReset(email: address)
                sent = true
            } catch {
                errorMessage = AuthViewModel.changePasswordErrorMessage(error)
            }
            isSending = false
        }
    }
}
