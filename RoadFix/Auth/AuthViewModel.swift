//
//  AuthViewModel.swift
//  RoadFix
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    // True while a sign-in or sign-up request is running, so the button can
    // show a spinner and can't be tapped twice.
    @Published var isSubmitting: Bool = false

    // During sign-up the auth listener fires before the profile doc exists;
    // keep isSubmitting on until createUserProfile finishes.
    private var isCreatingAccount = false
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    init() {
        // Guards SwiftUI Previews (and any other early instantiation) that
        // never go through RoadFixApp.init(), which is the normal place
        // FirebaseApp.configure() runs. Calling configure() before any
        // Firebase API is required, or Auth.auth() below crashes.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // Firebase callbacks are Sendable closures, so each one hops back to
        // the main actor before touching this view model's state.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            Task { @MainActor in
                guard let self else { return }
                if let uid {
                    self.fetchUserProfile(uid: uid)
                } else {
                    self.currentUser = nil
                    self.isLoading = false
                }
            }
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    private func fetchUserProfile(uid: String) {
        db.collection("users").document(uid).getDocument { [weak self] snapshot, _ in
            let data = snapshot?.data()
            let email = data?["email"] as? String
            let role = data?["role"] as? String
            Task { @MainActor in
                guard let self else { return }
                defer { self.isLoading = false }
                guard let email, let role else {
                    self.errorMessage = "Could not load your account profile."
                    self.currentUser = nil
                    if !self.isCreatingAccount { self.isSubmitting = false }
                    return
                }
                self.currentUser = AppUser(id: uid, email: email, role: role)
                self.isSubmitting = false
            }
        }
    }

    func signIn(email: String, password: String) {
        errorMessage = nil
        isSubmitting = true
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            guard let error else { return }
            let message = Self.mapAuthError(error)
            Task { @MainActor in
                self?.errorMessage = message
                self?.isSubmitting = false
            }
        }
    }

    func signUp(email: String, password: String, staffCode: String?) {
        errorMessage = nil
        isSubmitting = true
        isCreatingAccount = true
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            let errorText = error.map { Self.mapAuthError($0) }
            let firebaseUser = result?.user
            Task { @MainActor in
                guard let self else { return }
                if let errorText {
                    self.errorMessage = errorText
                    self.finishSubmitting()
                    return
                }
                guard let firebaseUser else {
                    self.errorMessage = "Something went wrong, try again."
                    self.finishSubmitting()
                    return
                }
                let trimmedCode = staffCode?.trimmingCharacters(in: .whitespaces) ?? ""
                self.createUserProfile(
                    uid: firebaseUser.uid,
                    email: email,
                    staffCode: trimmedCode.isEmpty ? nil : trimmedCode,
                    createdUser: firebaseUser
                )
            }
        }
    }

    // The staff code is checked by the Firestore rules, not here: the client
    // can't read config/staffInviteCode. With a code we ask for a staff
    // profile; if the rules reject it (wrong code), we retry as a citizen,
    // so a wrong code still gives a working citizen account.
    private func createUserProfile(uid: String, email: String, staffCode: String?, createdUser: User) {
        let role = staffCode == nil ? AppUser.citizenRole : AppUser.staffRole
        var data: [String: Any] = [
            "email": email,
            "role": role,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let staffCode {
            data["staffCode"] = staffCode
        }
        db.collection("users").document(uid).setData(data) { [weak self] error in
            let failed = error != nil
            let rejectedByRules = (error as NSError?)?.code == FirestoreErrorCode.Code.permissionDenied.rawValue
            Task { @MainActor in
                guard let self else { return }
                if failed && staffCode != nil && rejectedByRules {
                    self.createUserProfile(uid: uid, email: email, staffCode: nil, createdUser: createdUser)
                    return
                }
                if failed {
                    // This is a Firestore error, not an Auth error — mapAuthError
                    // only understands AuthErrorCode, so don't route it there.
                    self.errorMessage = "Could not finish creating your account. Try again."
                    createdUser.delete(completion: nil)
                    try? Auth.auth().signOut()
                    self.finishSubmitting()
                    return
                }
                self.currentUser = AppUser(id: uid, email: email, role: role)
                self.errorMessage = nil
                self.finishSubmitting()
            }
        }
    }

    private func finishSubmitting() {
        isSubmitting = false
        isCreatingAccount = false
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            errorMessage = nil
            finishSubmitting()
        } catch {
            errorMessage = "Could not sign out. Try again."
        }
    }

    // Firebase only lets a password change through right after signing in,
    // so confirm the current password first, then set the new one.
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            throw NSError(domain: AuthErrors.domain, code: AuthErrorCode.userNotFound.rawValue)
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        _ = try await user.reauthenticate(with: credential)
        try await user.updatePassword(to: newPassword)
    }

    nonisolated static func changePasswordErrorMessage(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .wrongPassword, .invalidCredential:
            return "Your current password is incorrect."
        case .userNotFound, .userMismatch:
            return "You're signed out. Sign in and try again."
        case .tooManyRequests:
            return "Too many attempts. Wait a few minutes and try again."
        default:
            return mapAuthError(error)
        }
    }

    // Static and nonisolated so it can run inside Firebase's Sendable callbacks.
    private nonisolated static func mapAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return "Something went wrong, try again."
        }
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound:
            // Deliberately the same message for "wrong password" and "no
            // such account" — distinguishing them lets an attacker enumerate
            // which emails have accounts.
            return "Incorrect email or password."
        case .emailAlreadyInUse:
            return "An account with that email already exists."
        case .invalidEmail:
            return "That email address doesn't look right."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .networkError:
            return "Network error. Check your connection and try again."
        default:
            return "Something went wrong, try again."
        }
    }
}
