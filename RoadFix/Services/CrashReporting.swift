//
//  CrashReporting.swift
//  RoadFix
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Sentry

/// Sends crashes, app hangs and unexpected errors to Sentry so the team
/// hears about bugs without waiting for someone to report them.
///
/// The DSN comes from Sentry-Info.plist (git-ignored, like
/// GoogleService-Info.plist, because the repo is public). Without that file
/// Sentry stays off and the app works as before.
///
/// nonisolated because Firebase calls back on background threads, and the
/// Sentry SDK is safe to use from any thread.
nonisolated enum CrashReporting {
    private static let configFile = "Sentry-Info"
    private static let dsnKey = "SENTRY_DSN"

    static func start() {
        // Unit tests launch the app too; keep their runs out of Sentry.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let dsn = configuredDSN() else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
            // Privacy: no emails, IP addresses, screenshots or view
            // hierarchies leave the device (see the Privacy Policy).
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            // Errors and crashes only; performance tracing is off for now.
            options.enableAutoPerformanceTracing = false
            options.enableAppHangTracking = true
        }
    }

    /// Reports an unexpected error with a short, data-free description of
    /// what the app was doing, e.g. "submit report". A lost or missing
    /// connection is skipped: that's the user's network, not a bug.
    static func record(_ error: Error, action: String) {
        guard SentrySDK.isEnabled, !isConnectionProblem(error) else { return }
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: action, key: "action")
        }
    }

    /// Reports something that went wrong without an Error to attach.
    static func record(message: String, action: String) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setTag(value: action, key: "action")
            scope.setLevel(.error)
        }
    }

    static func isConnectionProblem(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case FirestoreErrorDomain:
            let code = FirestoreErrorCode.Code(rawValue: nsError.code)
            if code == .unavailable || code == .deadlineExceeded { return true }
        case AuthErrorDomain:
            if AuthErrorCode(rawValue: nsError.code) == .networkError { return true }
        case NSURLErrorDomain:
            let offline: [URLError.Code] = [
                .notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                .internationalRoamingOff, .dataNotAllowed
            ]
            if offline.contains(URLError.Code(rawValue: nsError.code)) { return true }
        default:
            break
        }
        // Firebase often wraps the network error that caused the failure.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isConnectionProblem(underlying)
        }
        return false
    }

    private static func configuredDSN() -> String? {
        guard let url = Bundle.main.url(forResource: configFile, withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let dsn = values[dsnKey] as? String,
              !dsn.isEmpty else {
            return nil
        }
        return dsn
    }
}
