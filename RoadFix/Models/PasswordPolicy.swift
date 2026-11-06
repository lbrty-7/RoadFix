import Foundation

/// Client-side password and email rules shared by sign-up and change password.
/// Firebase's own password policy (set in the console) is the server-side
/// check; this one gives instant feedback and blocks the most common passwords.
enum PasswordPolicy {
    static let minimumLength = 12

    // Lowercased. The most common passwords of 12+ characters from public
    // breach lists, plus obvious app-specific ones.
    private static let commonPasswords: Set<String> = [
        "123456789012", "1234567890123", "12345678901234", "123456789012345",
        "1234567890123456", "qwertyuiopas", "qwertyuiop123", "qwerty123456",
        "password1234", "password12345", "password123456", "passwordpassword",
        "111111111111", "000000000000", "aaaaaaaaaaaa", "abcdefghijkl",
        "abc123456789", "iloveyou1234", "1q2w3e4r5t6y", "1qaz2wsx3edc",
        "qazwsxedcrfv", "zaq12wsxcde3", "asdfghjklzxc", "letmein12345",
        "welcome12345", "administrator", "changeme1234", "roadfix12345",
        "roadfixroadfix", "chisinau2026", "moldova12345", "parola123456",
        "parolaparola"
    ]

    /// Nil when the password is acceptable, otherwise the reason it isn't.
    static func problem(with password: String, email: String = "") -> String? {
        if password.count < minimumLength {
            return String(localized: "Use at least 12 characters.")
        }
        let lowered = password.lowercased()
        if commonPasswords.contains(lowered) || Set(lowered).count <= 2 {
            return String(localized: "This password is too common. Choose another one.")
        }
        let localPart = normalizedEmail(email).split(separator: "@").first.map(String.init) ?? ""
        if localPart.count >= 4 && lowered.contains(localPart) {
            return String(localized: "Don't use your email address in your password.")
        }
        return nil
    }

    static func isAcceptable(_ password: String, email: String = "") -> Bool {
        problem(with: password, email: email) == nil
    }

    /// Trimmed and lowercased, so "  Ana@Mail.com " and "ana@mail.com" are
    /// the same account.
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
