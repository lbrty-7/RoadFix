//
//  LoginView.swift
//  RoadFix
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    @FocusState private var focus: AuthFocus?

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            AuthScreen {
                Spacer(minLength: 0)

                AuthHeader(title: "RoadFix", subtitle: "Report road issues in your city.")

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
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        contentType: .password,
                        focus: $focus,
                        field: .password
                    )
                    .submitLabel(.go)
                    .onSubmit(submit)
                }

                AuthErrorText(message: authViewModel.errorMessage)

                AuthPrimaryButton(
                    title: "Log In",
                    isLoading: authViewModel.isSubmitting,
                    isEnabled: canSubmit,
                    action: submit
                )

                Button("Forgot Password?") {
                    showForgotPassword = true
                }
                .font(.footnote)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("New to RoadFix?")
                        .foregroundStyle(.secondary)
                    Button("Create Account") {
                        showSignUp = true
                    }
                    .fontWeight(.semibold)
                }
                .font(.footnote)
            }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView(email: email)
            }
        }
    }

    private func submit() {
        guard canSubmit, !authViewModel.isSubmitting else { return }
        focus = nil
        authViewModel.signIn(email: email, password: password)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
