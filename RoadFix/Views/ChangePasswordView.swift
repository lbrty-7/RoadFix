import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private var validationMessage: String? {
        if !newPassword.isEmpty && newPassword.count < 6 {
            return String(localized: "The new password must be at least 6 characters.")
        }
        if !confirmPassword.isEmpty && newPassword != confirmPassword {
            return String(localized: "The new passwords don't match.")
        }
        return nil
    }

    private var canSave: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 6
            && newPassword == confirmPassword
            && !isSaving
    }

    var body: some View {
        Form {
            Section("Current Password") {
                SecureField("Current password", text: $currentPassword)
                    .textContentType(.password)
            }

            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } header: {
                Text("New Password")
            } footer: {
                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
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
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Change Password")
                    }
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password Changed", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Use your new password the next time you log in.")
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await authViewModel.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                showSuccess = true
            } catch {
                errorMessage = AuthViewModel.changePasswordErrorMessage(error)
            }
            isSaving = false
        }
    }
}
