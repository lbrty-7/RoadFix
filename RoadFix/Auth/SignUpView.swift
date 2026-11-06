//
//  SignUpView.swift
//  RoadFix
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isStaff = false
    @State private var staffCode = ""
    @State private var isOldEnough = false
    @State private var acceptsTerms = false
    @State private var legalDocument: LegalDocument?
    @FocusState private var focus: AuthFocus?

    private var passwordProblem: String? {
        PasswordPolicy.problem(with: password, email: email)
    }

    // Shown once something is typed, so an empty form isn't covered in errors.
    private var passwordHint: String? {
        if !password.isEmpty, let passwordProblem { return passwordProblem }
        if !confirmPassword.isEmpty && password != confirmPassword {
            return String(localized: "The passwords don't match.")
        }
        return nil
    }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") &&
        passwordProblem == nil &&
        password == confirmPassword &&
        isOldEnough && acceptsTerms
    }

    var body: some View {
        AuthScreen {
            Spacer(minLength: 0)

            AuthHeader(title: "Create Account", subtitle: "Join RoadFix to report issues around your city.")

            AuthCard {
                AuthField(
                    systemImage: "envelope",
                    placeholder: "Email",
                    text: $email,
                    contentType: .username,
                    keyboard: .emailAddress,
                    focus: $focus,
                    field: .email
                )
                .submitLabel(.next)
                .onSubmit { focus = .password }

                AuthCardDivider()

                AuthField(
                    systemImage: "lock",
                    placeholder: "Password (min 12 characters)",
                    text: $password,
                    isSecure: true,
                    contentType: .newPassword,
                    focus: $focus,
                    field: .password
                )
                .submitLabel(.next)
                .onSubmit { focus = .confirmPassword }

                AuthCardDivider()

                AuthField(
                    systemImage: "lock.rotation",
                    placeholder: "Confirm Password",
                    text: $confirmPassword,
                    isSecure: true,
                    contentType: .newPassword,
                    focus: $focus,
                    field: .confirmPassword
                )
                .submitLabel(isStaff ? .next : .go)
                .onSubmit {
                    if isStaff { focus = .staffCode } else { submit() }
                }
            }

            DisclosureGroup("I'm staff", isExpanded: $isStaff) {
                AuthCard {
                    AuthField(
                        systemImage: "key",
                        placeholder: "Staff invite code",
                        text: $staffCode,
                        focus: $focus,
                        field: .staffCode
                    )
                    .submitLabel(.go)
                    .onSubmit(submit)
                }
                .padding(.top, 8)
            }
            .tint(.primary)
            .padding(.horizontal, 4)

            if let passwordHint {
                Text(passwordHint)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("I'm 16 or older", isOn: $isOldEnough)
                Toggle(isOn: $acceptsTerms) {
                    Text("I agree to the Terms of Use and the Privacy Policy")
                }
                HStack(spacing: 16) {
                    Button("Terms of Use") { legalDocument = .terms }
                    Button("Privacy Policy") { legalDocument = .privacy }
                }
                .font(.footnote.weight(.semibold))
            }
            .toggleStyle(CheckboxToggleStyle())
            .padding(.horizontal, 4)

            AuthErrorText(message: authViewModel.errorMessage)

            AuthPrimaryButton(
                title: "Create Account",
                isLoading: authViewModel.isSubmitting,
                isEnabled: canSubmit,
                action: submit
            )

            Spacer(minLength: 0)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $legalDocument) { document in
            NavigationStack {
                LegalDocumentView(document: document)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { legalDocument = nil }
                        }
                    }
            }
        }
    }

    private func submit() {
        guard canSubmit, !authViewModel.isSubmitting else { return }
        focus = nil
        let code = isStaff ? staffCode : nil
        authViewModel.signUp(email: email, password: password, staffCode: code)
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environmentObject(AuthViewModel())
    }
}
