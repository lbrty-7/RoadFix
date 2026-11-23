//
//  RoadFixTests.swift
//  RoadFixTests
//

import Testing
import UIKit
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
@testable import RoadFix

// A spot in central Chișinău; ~0.0001° of latitude is ~11 m.
private let center = CLLocationCoordinate2D(latitude: 47.0245, longitude: 28.8322)

private func makeReport(
    id: String = UUID().uuidString,
    category: ReportCategory = .pothole,
    description: String = "Deep pothole",
    address: String? = nil,
    latitude: Double = center.latitude,
    longitude: Double = center.longitude,
    status: ReportStatus = .reported,
    upvotes: Int = 0,
    createdAt: Date = Date()
) -> Report {
    Report(
        id: id,
        category: category,
        description: description,
        hasPhoto: false,
        address: address,
        latitude: latitude,
        longitude: longitude,
        status: status,
        upvoterIds: (0..<upvotes).map { "user\($0)" },
        reporterId: "reporter",
        createdAt: createdAt
    )
}

@Suite("Reading reports from Firestore")
struct ReportParsingTests {
    @Test func parsesAllFields() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let changed = Date(timeIntervalSince1970: 1_700_086_400)
        let data: [String: Any] = [
            "category": "streetlight",
            "description": "Light is out",
            "latitude": 47.0,
            "longitude": 28.8,
            "status": "inProgress",
            "reporterId": "abc",
            "hasPhoto": true,
            "address": "Strada Pușkin 1",
            "upvoterIds": ["u1", "u2"],
            "createdAt": Timestamp(date: created),
            "staffNote": "Crew booked",
            "statusHistory": [["status": "inProgress", "date": Timestamp(date: changed)]]
        ]

        let report = try #require(ReportService.report(id: "r1", data: data))

        #expect(report.id == "r1")
        #expect(report.category == .streetlight)
        #expect(report.status == .inProgress)
        #expect(report.hasPhoto)
        #expect(report.address == "Strada Pușkin 1")
        #expect(report.upvoteCount == 2)
        #expect(report.createdAt == created)
        #expect(report.staffNote == "Crew booked")
        #expect(report.statusHistory == [StatusChange(status: .inProgress, date: changed)])
    }

    @Test func olderReportsWithoutNewFieldsStillLoad() throws {
        let data: [String: Any] = [
            "category": "pothole",
            "description": "Hole",
            "latitude": 47.0,
            "longitude": 28.8,
            "status": "reported",
            "reporterId": "abc"
        ]

        let report = try #require(ReportService.report(id: "r2", data: data))

        #expect(!report.hasPhoto)
        #expect(report.address == nil)
        #expect(report.upvoterIds.isEmpty)
        #expect(report.staffNote == nil)
        #expect(report.statusHistory.isEmpty)
    }

    @Test(arguments: ["category", "description", "latitude", "longitude", "status", "reporterId"])
    func missingRequiredFieldIsSkipped(field: String) {
        var data: [String: Any] = [
            "category": "pothole",
            "description": "Hole",
            "latitude": 47.0,
            "longitude": 28.8,
            "status": "reported",
            "reporterId": "abc"
        ]
        data.removeValue(forKey: field)
        #expect(ReportService.report(id: "r3", data: data) == nil)
    }

    @Test func unknownStatusIsSkipped() {
        let data: [String: Any] = [
            "category": "pothole",
            "description": "Hole",
            "latitude": 47.0,
            "longitude": 28.8,
            "status": "archived",
            "reporterId": "abc"
        ]
        #expect(ReportService.report(id: "r4", data: data) == nil)
    }
}

@Suite("Report description")
struct ReportDescriptionTests {
    @Test func trimsSpacesAndBlankLinesAroundTheText() {
        #expect(ReportService.cleanedDescription("Large pothole near the tram stop.  ") == "Large pothole near the tram stop.")
        #expect(ReportService.cleanedDescription("\n\n  Light is out\t\n") == "Light is out")
    }

    @Test func keepsLineBreaksAndSpacesInsideTheText() {
        #expect(ReportService.cleanedDescription(" Deep hole.\n\nNear the  crossing. ") == "Deep hole.\n\nNear the  crossing.")
    }

    @Test func whitespaceOnlyBecomesEmpty() {
        #expect(ReportService.cleanedDescription(" \n\t ").isEmpty)
    }
}

@Suite("Photo compression")
struct PhotoCompressionTests {
    private func noisyImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            // Random colored blocks compress poorly, like a real photo.
            for x in stride(from: 0, to: width, by: 8) {
                for y in stride(from: 0, to: height, by: 8) {
                    UIColor(
                        red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1), alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
    }

    @Test func largePhotoFitsFirestoreLimitAndIsResized() throws {
        let data = try #require(ReportService.compressedJPEG(noisyImage(width: 4000, height: 3000)))
        #expect(data.count < 900 * 1024)

        let decoded = try #require(UIImage(data: data))
        #expect(max(decoded.size.width, decoded.size.height) == 1280)
    }

    @Test func smallPhotoKeepsItsSize() throws {
        let data = try #require(ReportService.compressedJPEG(noisyImage(width: 400, height: 300)))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size == CGSize(width: 400, height: 300))
    }

    @Test func thumbnailIsSmallAndFitsItsLimit() throws {
        let data = try #require(ReportService.thumbnailJPEG(noisyImage(width: 4000, height: 3000)))
        #expect(data.count < ReportService.maxThumbnailBytes)

        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size == CGSize(width: 192, height: 144))
    }
}

@Suite("Map pin groups")
struct ReportClusterTests {
    @Test func nearbyReportsShareOnePin() {
        let a = makeReport(id: "a")
        let b = makeReport(id: "b", latitude: center.latitude + 0.0001) // ~11 m
        let far = makeReport(id: "far", latitude: center.latitude + 0.05) // ~5.5 km

        let clusters = ReportCluster.group([far, b, a], cellSize: 0.01)

        #expect(clusters.map { $0.reports.map(\.id) } == [["a", "b"], ["far"]])
        #expect(clusters[0].id == "a")
    }

    @Test func pinIsInTheMiddleOfItsReports() {
        let south = makeReport(latitude: 47.003)
        let north = makeReport(latitude: 47.005)
        let clusters = ReportCluster.group([south, north], cellSize: 0.01)
        #expect(clusters.count == 1)
        #expect(abs(clusters[0].coordinate.latitude - 47.004) < 0.000001)
    }

    @Test func zoomedInShowsEveryReport() {
        #expect(ReportCluster.cellSize(forLatitudeSpan: 0.004) == 0)
        let reports = [makeReport(id: "a"), makeReport(id: "b")]
        #expect(ReportCluster.group(reports, cellSize: 0).count == 2)
        #expect(abs(ReportCluster.cellSize(forLatitudeSpan: 0.12) - 0.01) < 0.000001)
    }
}

@Suite("Duplicate detection")
struct DuplicateDetectionTests {
    @Test func findsNearbyOpenReportOfSameCategory() {
        let nearby = makeReport(latitude: center.latitude + 0.0002) // ~22 m
        let found = Report.possibleDuplicates(of: .pothole, near: center, in: [nearby])
        #expect(found.map(\.id) == [nearby.id])
    }

    @Test func ignoresFarAwayDifferentCategoryAndResolved() {
        let farAway = makeReport(latitude: center.latitude + 0.001) // ~110 m
        let otherCategory = makeReport(category: .streetlight)
        let resolved = makeReport(status: .resolved)

        let found = Report.possibleDuplicates(of: .pothole, near: center, in: [farAway, otherCategory, resolved])

        #expect(found.isEmpty)
    }

    @Test func nearestComesFirst() {
        let closer = makeReport(latitude: center.latitude + 0.0001)
        let further = makeReport(latitude: center.latitude + 0.0003)
        let found = Report.possibleDuplicates(of: .pothole, near: center, in: [further, closer])
        #expect(found.map(\.id) == [closer.id, further.id])
    }
}

@Suite("Dashboard sorting and search")
struct DashboardTests {
    private let old = makeReport(id: "old", upvotes: 5, createdAt: Date(timeIntervalSince1970: 100))
    private let middle = makeReport(id: "middle", upvotes: 1, createdAt: Date(timeIntervalSince1970: 200))
    private let new = makeReport(id: "new", upvotes: 5, createdAt: Date(timeIntervalSince1970: 300))

    @Test func sortsNewestAndOldest() {
        #expect(ReportSortOrder.newest.sorted([old, new, middle]).map(\.id) == ["new", "middle", "old"])
        #expect(ReportSortOrder.oldest.sorted([new, old, middle]).map(\.id) == ["old", "middle", "new"])
    }

    @Test func mostUpvotedBreaksTiesByNewest() {
        #expect(ReportSortOrder.mostUpvoted.sorted([old, middle, new]).map(\.id) == ["new", "old", "middle"])
    }

    @Test func searchMatchesDescriptionAddressAndIgnoresCase() {
        let report = makeReport(description: "Broken curb", address: "Bulevardul Ștefan cel Mare")
        #expect(report.matches(search: "curb"))
        #expect(report.matches(search: "ȘTEFAN"))
        #expect(report.matches(search: "   "))
        #expect(!report.matches(search: "streetlight"))
    }
}

@Suite("Password and email rules")
struct PasswordPolicyTests {
    @Test func rejectsShortPasswords() {
        #expect(!PasswordPolicy.isAcceptable("short1"))
        #expect(!PasswordPolicy.isAcceptable("elevenchars"))
        #expect(PasswordPolicy.isAcceptable("bright-river-42"))
    }

    @Test func rejectsCommonPasswords() {
        #expect(!PasswordPolicy.isAcceptable("Password1234"))
        #expect(!PasswordPolicy.isAcceptable("123456789012"))
        #expect(!PasswordPolicy.isAcceptable("abababababab"))
    }

    @Test func rejectsPasswordContainingEmail() {
        #expect(!PasswordPolicy.isAcceptable("ion.popescu2026", email: "Ion.Popescu@mail.md"))
        #expect(PasswordPolicy.isAcceptable("quiet-harbor-77", email: "ion.popescu@mail.md"))
    }

    @Test func normalizesEmail() {
        #expect(PasswordPolicy.normalizedEmail("  Ana@Mail.COM \n") == "ana@mail.com")
    }
}

struct CrashReportingTests {
    @Test func connectionProblemsAreSkipped() {
        #expect(CrashReporting.isConnectionProblem(NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.Code.unavailable.rawValue)))
        #expect(CrashReporting.isConnectionProblem(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        #expect(CrashReporting.isConnectionProblem(URLError(.timedOut)))
    }

    @Test func wrappedConnectionProblemIsSkipped() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        let wrapped = NSError(domain: "FIRAuthErrorDomain", code: 17999, userInfo: [NSUnderlyingErrorKey: offline])
        #expect(CrashReporting.isConnectionProblem(wrapped))
    }

    @Test func realFailuresAreReported() {
        #expect(!CrashReporting.isConnectionProblem(NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.Code.permissionDenied.rawValue)))
        #expect(!CrashReporting.isConnectionProblem(NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.Code.internal.rawValue)))
        #expect(!CrashReporting.isConnectionProblem(NSError(domain: "RoadFix", code: 1)))
    }
}

// MARK: - Sign-in and account errors

private func authError(_ code: AuthErrorCode) -> NSError {
    NSError(domain: AuthErrorDomain, code: code.rawValue)
}

@Suite("Sign-in error messages")
struct AuthErrorMessageTests {
    @Test func wrongPasswordAndUnknownAccountLookTheSame() {
        // Different messages would tell an attacker which emails have accounts.
        let wrongPassword = AuthViewModel.mapAuthError(authError(.wrongPassword))
        #expect(wrongPassword == String(localized: "Incorrect email or password."))
        #expect(AuthViewModel.mapAuthError(authError(.userNotFound)) == wrongPassword)
        #expect(AuthViewModel.mapAuthError(authError(.invalidCredential)) == wrongPassword)
    }

    @Test func networkErrorGivesTheNetworkMessage() {
        #expect(AuthViewModel.mapAuthError(authError(.networkError))
            == String(localized: "Network error. Check your connection and try again."))
    }

    @Test func signUpProblemsHaveTheirOwnMessages() {
        #expect(AuthViewModel.mapAuthError(authError(.emailAlreadyInUse))
            == String(localized: "An account with that email already exists."))
        #expect(AuthViewModel.mapAuthError(authError(.invalidEmail))
            == String(localized: "That email address doesn't look right."))
        #expect(AuthViewModel.mapAuthError(authError(.weakPassword))
            == String(localized: "Password must be at least 12 characters."))
        #expect(AuthViewModel.mapAuthError(authError(.tooManyRequests))
            == String(localized: "Too many attempts. Wait a few minutes and try again."))
    }

    @Test func unknownErrorsGetTheGenericMessage() {
        let generic = String(localized: "Something went wrong, try again.")
        #expect(AuthViewModel.mapAuthError(NSError(domain: "RoadFix", code: 999_999)) == generic)
        #expect(AuthViewModel.mapAuthError(authError(.internalError)) == generic)
    }

    @Test func changePasswordExplainsAWrongCurrentPassword() {
        #expect(AuthViewModel.changePasswordErrorMessage(authError(.wrongPassword))
            == String(localized: "Your current password is incorrect."))
        #expect(AuthViewModel.changePasswordErrorMessage(authError(.userMismatch))
            == String(localized: "You're signed out. Sign in and try again."))
        // Anything else falls back to the sign-in messages.
        #expect(AuthViewModel.changePasswordErrorMessage(authError(.networkError))
            == AuthViewModel.mapAuthError(authError(.networkError)))
    }
}

// MARK: - Report rules

@Suite("Report limits")
struct ReportLimitTests {
    @Test func textIsCutAtTheLimit() {
        let long = String(repeating: "a", count: ReportService.maxDescriptionLength + 1)
        #expect(ReportService.limited(long, to: ReportService.maxDescriptionLength).count == ReportService.maxDescriptionLength)
        #expect(ReportService.limited("Deep hole", to: ReportService.maxDescriptionLength) == "Deep hole")
        #expect(ReportService.limited("Crew booked for Monday", to: 4) == "Crew")
    }

    @Test func anEmojiCountsAsOneCharacter() {
        #expect(ReportService.limited("👍👍👍", to: 2) == "👍👍")
    }

    // firestore.rules allows twice the app's limits (2000 and 1000), since
    // it counts an emoji as more than one character.
    @Test func limitsFitTheRules() {
        #expect(ReportService.maxDescriptionLength * 2 <= 2000)
        #expect(ReportService.maxStaffNoteLength * 2 <= 1000)
        let emoji = ReportService.limited(String(repeating: "👍", count: 2000), to: ReportService.maxDescriptionLength)
        #expect(emoji.utf16.count <= 2000)
    }

    @Test func oneReportPerMinute() {
        let sent = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(ReportService.secondsUntilNextReport(after: nil) == nil)
        #expect(ReportService.secondsUntilNextReport(after: sent, now: sent) == 60)
        #expect(ReportService.secondsUntilNextReport(after: sent, now: sent + 20) == 40)
        // Rounded up, so it never says "0 s" while still blocked.
        #expect(ReportService.secondsUntilNextReport(after: sent, now: sent + 59.5) == 1)
        #expect(ReportService.secondsUntilNextReport(after: sent, now: sent + 60) == nil)
        #expect(ReportService.secondsUntilNextReport(after: sent, now: sent + 3600) == nil)
    }

    @Test func submitOutcomes() {
        #expect(SubmitOutcome.failed("No").isFailure)
        #expect(!SubmitOutcome.sent.isFailure)
        #expect(!SubmitOutcome.queued.isFailure)
    }

    @Test func pendingSubmitFinishesOnce() {
        var outcomes: [SubmitOutcome] = []
        let submit = PendingSubmit { outcomes.append($0) }
        #expect(!submit.isFinished)
        submit.finish(.queued)
        submit.finish(.sent) // the server's answer arriving later is ignored
        #expect(submit.isFinished)
        #expect(outcomes == [.queued])
    }
}

// MARK: - More Sentry filtering

@Suite("Sentry filtering")
struct MoreCrashReportingTests {
    @Test func moreConnectionProblemsAreSkipped() {
        #expect(CrashReporting.isConnectionProblem(authError(.networkError)))
        #expect(CrashReporting.isConnectionProblem(NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.Code.deadlineExceeded.rawValue)))
        #expect(CrashReporting.isConnectionProblem(URLError(.cannotFindHost)))
    }

    @Test func connectionProblemWrappedTwiceIsSkipped() {
        let offline = URLError(.notConnectedToInternet) as NSError
        let middle = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.Code.unknown.rawValue, userInfo: [NSUnderlyingErrorKey: offline])
        let outer = NSError(domain: "RoadFix", code: 1, userInfo: [NSUnderlyingErrorKey: middle])
        #expect(CrashReporting.isConnectionProblem(outer))
    }

    @Test func otherAuthAndURLErrorsAreReported() {
        #expect(!CrashReporting.isConnectionProblem(authError(.wrongPassword)))
        #expect(!CrashReporting.isConnectionProblem(URLError(.badURL)))
        #expect(!CrashReporting.isConnectionProblem(URLError(.badServerResponse)))
    }
}

// MARK: - More password rules

@Suite("More password rules")
struct MorePasswordPolicyTests {
    @Test func exactlyTwelveCharactersIsEnough() {
        #expect(PasswordPolicy.isAcceptable("river-stone7"))
        #expect(!PasswordPolicy.isAcceptable("river-stone"))
    }

    @Test func commonPasswordsAreCaughtInAnyCase() {
        #expect(!PasswordPolicy.isAcceptable("PASSWORD1234"))
        #expect(!PasswordPolicy.isAcceptable("RoadFix12345"))
    }

    @Test func twoRepeatedCharactersAreTooCommon() {
        #expect(!PasswordPolicy.isAcceptable("aaaabbbbaaaa"))
        #expect(PasswordPolicy.isAcceptable("aaabbbcccaaa"))
    }

    @Test func shortEmailNamesAreNotChecked() {
        // A 3-letter name like "ana" would block too many passwords.
        #expect(PasswordPolicy.isAcceptable("banana-river-26", email: "ana@mail.md"))
    }

    @Test func eachProblemHasItsOwnMessage() {
        #expect(PasswordPolicy.problem(with: "short") == String(localized: "Use at least 12 characters."))
        #expect(PasswordPolicy.problem(with: "password1234") == String(localized: "This password is too common. Choose another one."))
        #expect(PasswordPolicy.problem(with: "maria.ionescu-77", email: "maria.ionescu@mail.md")
            == String(localized: "Don't use your email address in your password."))
        #expect(PasswordPolicy.problem(with: "quiet-harbor-77") == nil)
    }
}
