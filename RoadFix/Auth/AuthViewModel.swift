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
    // firestore.rules only accept new reports from verified addresses, so
    // NewReportView asks the user to confirm their email first.
    @Published var isEmailVerified: Bool = false

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
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            let data = snapshot?.data()
            let email = data?["email"] as? String
            let role = data?["role"] as? String
            Task { @MainActor in
                guard let self else { return }
                defer { self.isLoading = false }
                guard let email, let role else {
                    // Right after sign-up the profile doesn't exist yet, so
                    // that case isn't a bug.
                    if let error {
                        CrashReporting.record(error, action: "load profile")
                    } else if !self.isCreatingAccount {
                        CrashReporting.record(message: "User profile missing or incomplete", action: "load profile")
                    }
                    self.errorMessage = String(localized: "Could not load your account profile.")
                    self.currentUser = nil
                    if !self.isCreatingAccount { self.isSubmitting = false }
                    return
                }
                self.currentUser = AppUser(id: uid, email: email, role: role)
                self.isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? false
                self.isSubmitting = false
            }
        }
    }

    func signIn(email: String, password: String) {
        errorMessage = nil
        isSubmitting = true
        Auth.auth().signIn(withEmail: PasswordPolicy.normalizedEmail(email), password: password) { [weak self] _, error in
            guard let error else { return }
            let message = Self.mapAuthError(error)
            Task { @MainActor in
                self?.errorMessage = message
                self?.isSubmitting = false
            }
        }
    }

    func signUp(email: String, password: String, staffCode: String?) {
        let email = PasswordPolicy.normalizedEmail(email)
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
                    self.errorMessage = String(localized: "Something went wrong, try again.")
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
            "createdAt": FieldValue.serverTimestamp(),
            // Sign-up can't finish without ticking the terms and age boxes,
            // so this records when that consent was given.
            "termsAcceptedAt": FieldValue.serverTimestamp()
        ]
        if let staffCode {
            data["staffCode"] = staffCode
        }
        db.collection("users").document(uid).setData(data) { [weak self] error in
            let failed = error != nil
            // A refused staff code is expected and retried as a citizen.
            if let error, !(staffCode != nil && (error as NSError).code == FirestoreErrorCode.Code.permissionDenied.rawValue) {
                CrashReporting.record(error, action: "create profile")
            }
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
                    self.errorMessage = String(localized: "Could not finish creating your account. Try again.")
                    createdUser.delete(completion: nil)
                    try? Auth.auth().signOut()
                    self.finishSubmitting()
                    return
                }
                self.currentUser = AppUser(id: uid, email: email, role: role)
                self.isEmailVerified = false
                self.errorMessage = nil
                self.finishSubmitting()
                createdUser.sendEmailVerification(completion: nil)
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
            isEmailVerified = false
            errorMessage = nil
            finishSubmitting()
        } catch {
            CrashReporting.record(error, action: "sign out")
            errorMessage = String(localized: "Could not sign out. Try again.")
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

    // Firebase sends the email and hosts the reset page. It doesn't say
    // whether an account exists for the address, so neither does the app.
    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: PasswordPolicy.normalizedEmail(email))
    }

    func resendVerificationEmail() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.sendEmailVerification()
    }

    // After the user taps the link in the email, reload the account and
    // fetch a fresh ID token: the rules read email_verified from the token,
    // and the cached one still says false.
    func refreshEmailVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        try? await user.reload()
        if user.isEmailVerified {
            _ = try? await user.getIDTokenResult(forcingRefresh: true)
        }
        isEmailVerified = user.isEmailVerified
    }

    // Removes everything the user created — their reports, report photos,
    // their upvotes on other reports and their profile — then the Firebase
    // account itself (App Store guideline 5.1.1(v)).
    // Signing in again first is required by Firebase to delete an account.
    func deleteAccount(password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            throw NSError(domain: AuthErrors.domain, code: AuthErrorCode.userNotFound.rawValue)
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        _ = try await user.reauthenticate(with: credential)

        let reports = try await db.collection("reports")
            .whereField("reporterId", isEqualTo: user.uid)
            .getDocuments()
        // Each report is 3 deletes (report, photo and thumbnail). The rules
        // look up the report for each photo and thumbnail, and Firestore
        // allows 20 lookups per batch (the user's profile is one), so a batch
        // of 20 or more reports is refused. 15 leaves a margin.
        let reportsPerBatch = 15
        for chunk in stride(from: 0, to: reports.documents.count, by: reportsPerBatch) {
            let batch = db.batch()
            for document in reports.documents[chunk..<min(chunk + reportsPerBatch, reports.documents.count)] {
                batch.deleteDocument(document.reference)
                batch.deleteDocument(db.collection("reportPhotos").document(document.documentID))
                batch.deleteDocument(db.collection("reportThumbnails").document(document.documentID))
            }
            try await batch.commit()
        }
        try await removeUpvotes(of: user.uid)
        try await db.collection("users").document(user.uid).delete()
        try await user.delete()
        // The auth listener sees the signed-out state and shows LoginView.
    }

    // Takes the user's ID out of upvoterIds on every report they upvoted, so
    // those reports stop counting a deleted account's vote. firestore.rules
    // caps lists of other people's reports at 500, so this works in pages:
    // each removed upvote drops the report from the query, and the next page
    // picks up the rest. Each batch (at most 500 writes) is one page.
    private func removeUpvotes(of uid: String) async throws {
        let upvoted = db.collection("reports")
            .whereField("upvoterIds", arrayContains: uid)
            .limit(to: ReportService.listLimit)
        while true {
            let page = try await upvoted.getDocuments()
            guard !page.documents.isEmpty else { return }
            let batch = db.batch()
            for document in page.documents {
                batch.updateData(["upvoterIds": FieldValue.arrayRemove([uid])], forDocument: document.reference)
            }
            try await batch.commit()
        }
    }

    nonisolated static func changePasswordErrorMessage(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .wrongPassword, .invalidCredential:
            return String(localized: "Your current password is incorrect.")
        case .userNotFound, .userMismatch:
            return String(localized: "You're signed out. Sign in and try again.")
        case .tooManyRequests:
            return String(localized: "Too many attempts. Wait a few minutes and try again.")
        default:
            return mapAuthError(error)
        }
    }

    // Static and nonisolated so it can run inside Firebase's Sendable callbacks.
    // Wrong passwords, taken emails and the like are the user's input, not
    // bugs; only errors that fall through to the generic message go to Sentry.
    private nonisolated static func mapAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            CrashReporting.record(error, action: "account")
            return String(localized: "Something went wrong, try again.")
        }
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound:
            // Deliberately the same message for "wrong password" and "no
            // such account" — distinguishing them lets an attacker enumerate
            // which emails have accounts.
            return String(localized: "Incorrect email or password.")
        case .emailAlreadyInUse:
            return String(localized: "An account with that email already exists.")
        case .invalidEmail:
            return String(localized: "That email address doesn't look right.")
        case .weakPassword, .passwordDoesNotMeetRequirements:
            return String(localized: "Password must be at least 12 characters.")
        case .tooManyRequests:
            return String(localized: "Too many attempts. Wait a few minutes and try again.")
        case .networkError:
            return String(localized: "Network error. Check your connection and try again.")
        default:
            CrashReporting.record(error, action: "account")
            return String(localized: "Something went wrong, try again.")
        }
    }
}
