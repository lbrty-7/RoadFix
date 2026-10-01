import SwiftUI

/// Permanently deletes the signed-in account and everything it created.
struct DeleteAccountView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var password = ""
    @State private var isDeleting = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Label("This can't be undone.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Deleting your account permanently removes your login, your profile and every report and photo you've submitted.")
            }

            Section {
                SecureField("Current password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Confirm It's You")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Text("Delete My Account")
                    }
                }
                .disabled(password.isEmpty || isDeleting)
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account and All Reports", role: .destructive, action: deleteAccount)
        } message: {
            Text("Your reports and photos will be removed for everyone.")
        }
    }

    private func deleteAccount() {
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await authViewModel.deleteAccount(password: password)
                // Signed out now; RootView switches to the login screen.
            } catch {
                errorMessage = AuthViewModel.changePasswordErrorMessage(error)
                isDeleting = false
            }
        }
    }
}
