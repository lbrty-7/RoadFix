import Foundation
import CoreLocation
import MapKit
import UIKit
import Combine
import FirebaseAuth
import FirebaseFirestore

/// What happened to a new report when New Report can close.
enum SubmitOutcome: Equatable {
    case sent
    // Saved on the phone; Firestore sends it when the connection is back.
    case queued
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Calls a submit completion once: whichever comes first of the server's
/// answer, no connection, or the offlineGrace timeout.
final class PendingSubmit {
    private var completion: ((SubmitOutcome) -> Void)?

    init(_ completion: @escaping (SubmitOutcome) -> Void) {
        self.completion = completion
    }

    var isFinished: Bool { completion == nil }

    func finish(_ outcome: SubmitOutcome) {
        let completion = completion
        self.completion = nil
        completion?(outcome)
    }
}

class ReportService: ObservableObject {
    @Published var reports: [Report] = []
    // Every report the signed-in user filed, newest first. Loaded by its own
    // listener because `reports` stops at the newest listLimit in the city,
    // which would hide a user's older reports from My Reports.
    @Published var myReports: [Report] = []
    // Set when a write fails; ContentView shows it and clears it.
    @Published var actionError: String?
    // The status each of the user's reports had when they last opened it,
    // kept on the device. A different current status means staff changed
    // it since, which My Reports shows as "Updated".
    @Published private var seenStatuses: [String: String] = [:]

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var myReportsListener: ListenerRegistration?
    private let photoCache = NSCache<NSString, UIImage>()
    private var addressCache: [String: String] = [:]
    private static let maxPhotoBytes = 900 * 1024
    // firestore.rules allows twice these lengths, because it counts
    // characters differently from Swift (an emoji can count as several).
    static let maxDescriptionLength = 1000
    static let maxStaffNoteLength = 500
    static let minSecondsBetweenReports: TimeInterval = 60
    // How long Submit waits for the server before telling the user the
    // report is saved and will be sent later.
    static let offlineGrace: Duration = .seconds(5)
    private let connection = ConnectionMonitor()
    // The live listener loads at most this many (newest) reports, and
    // firestore.rules refuses larger lists so nobody can dump the collection.
    static let listLimit = 500
    private var lastSubmittedAt: Date?

    private var reportsCollection: CollectionReference {
        db.collection("reports")
    }

    private var photosCollection: CollectionReference {
        db.collection("reportPhotos")
    }

    // Live-syncs the newest reports (map, dashboard) and all of the user's
    // own reports (My Reports) so they update as soon as anyone submits,
    // upvotes or changes a status.
    func startListening() {
        guard listener == nil else { return }
        loadSeenStatuses()
        listener = reportsCollection
            .order(by: "createdAt", descending: true)
            .limit(to: Self.listLimit)
            .addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error {
                    print("Reports listener error: \(error.localizedDescription)")
                    CrashReporting.record(error, action: "listen to reports")
                }
                return
            }
            self.reports = Self.newestFirst(documents)
        }
        listenToMyReports()
    }

    // The user's own reports, with no limit: firestore.rules lets anyone list
    // all of their own reports. There's no order(by:) because combining it
    // with the reporterId filter would need a composite index; sorting a
    // single user's reports on the device is cheap. Metadata changes are
    // included so a report saved offline flips from "Waiting to Send" once
    // the server has it.
    private func listenToMyReports() {
        guard myReportsListener == nil, let uid = Auth.auth().currentUser?.uid else { return }
        myReportsListener = reportsCollection
            .whereField("reporterId", isEqualTo: uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error {
                    print("My reports listener error: \(error.localizedDescription)")
                    CrashReporting.record(error, action: "listen to my reports")
                }
                return
            }
            self.myReports = Self.newestFirst(documents)
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        myReportsListener?.remove()
        myReportsListener = nil
        myReports = []
    }

    /// A report from the city list or, for an older one of the user's own
    /// reports that isn't in it, from myReports.
    func report(withID id: String) -> Report? {
        reports.first { $0.id == id } ?? myReports.first { $0.id == id }
    }

    private static func newestFirst(_ documents: [QueryDocumentSnapshot]) -> [Report] {
        documents
            .compactMap { document in
                var parsed = report(id: document.documentID, data: document.data(with: .estimate))
                parsed?.isPending = document.metadata.hasPendingWrites
                return parsed
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Status updates seen by the reporter

    private var seenStatusesKey: String? {
        Auth.auth().currentUser.map { "seenStatuses.\($0.uid)" }
    }

    private func loadSeenStatuses() {
        guard let key = seenStatusesKey else { return }
        seenStatuses = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    /// True when staff changed the status since the reporter last opened it.
    /// Every report starts as "reported", so that's the default.
    func hasUnseenUpdate(_ report: Report) -> Bool {
        report.status.rawValue != (seenStatuses[report.id] ?? ReportStatus.reported.rawValue)
    }

    func markSeen(_ report: Report) {
        guard let key = seenStatusesKey, hasUnseenUpdate(report) else { return }
        seenStatuses[report.id] = report.status.rawValue
        UserDefaults.standard.set(seenStatuses, forKey: key)
    }

    func submitReport(
        category: ReportCategory,
        description: String,
        image: UIImage?,
        coordinate: CLLocationCoordinate2D,
        address: String?,
        completion: @escaping (SubmitOutcome) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failed(String(localized: "You're signed out. Sign in and try again.")))
            return
        }
        // firestore.rules enforces the same wait; checking here first gives a
        // clear message instead of a generic permission error.
        if let lastSubmittedAt, Date().timeIntervalSince(lastSubmittedAt) < Self.minSecondsBetweenReports {
            completion(.failed(String(localized: "You can send one report per minute. Wait a moment and try again.")))
            return
        }
        let document = reportsCollection.document()
        let photoData = image.flatMap(Self.compressedJPEG)
        var data: [String: Any] = [
            "category": category.rawValue,
            "description": Self.cleanedDescription(description),
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "status": ReportStatus.reported.rawValue,
            "upvoterIds": [String](),
            "reporterId": uid,
            "hasPhoto": photoData != nil,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let address {
            data["address"] = address
        }
        // The photo lives in its own reportPhotos/{reportId} doc so the live
        // reports listener doesn't download every image. A batch writes both
        // or neither, and lets firestore.rules check the photo's report owner.
        // lastReportAt on the user's profile is how firestore.rules limits
        // each account to one report per minute.
        let batch = db.batch()
        batch.setData(data, forDocument: document)
        batch.updateData(["lastReportAt": FieldValue.serverTimestamp()], forDocument: db.collection("users").document(uid))
        if let photoData {
            batch.setData(["data": photoData], forDocument: photosCollection.document(document.documentID))
        }
        commit(batch, completion: completion)
    }

    // batch.commit only calls back once the server confirms, which offline
    // can take minutes. Firestore keeps the write and sends it when the
    // connection is back, so the form is told the report is queued: at once
    // when there's no connection, or after offlineGrace when the server is
    // slow to answer. A refusal that arrives after that shows as actionError.
    private func commit(_ batch: WriteBatch, completion: @escaping (SubmitOutcome) -> Void) {
        let submit = PendingSubmit { [weak self] outcome in
            // A queued report counts too: the rules check the wait when it
            // reaches the server, so a second one sent offline would fail.
            if !outcome.isFailure {
                self?.lastSubmittedAt = Date()
            }
            completion(outcome)
        }
        batch.commit { [weak self] error in
            guard let error else { return submit.finish(.sent) }
            let message = Self.submitErrorMessage(for: error)
            if submit.isFinished {
                self?.actionError = message
            } else {
                submit.finish(.failed(message))
            }
        }
        if !connection.isOnline {
            submit.finish(.queued)
        } else {
            Task {
                try? await Task.sleep(for: Self.offlineGrace)
                submit.finish(.queued)
            }
        }
    }

    private static func submitErrorMessage(for error: Error) -> String {
        print("Submit report error: \(error.localizedDescription)")
        let code = FirestoreErrorCode.Code(rawValue: (error as NSError).code)
        // A refusal here is expected (unverified email or the one-per-minute
        // limit), so only other failures are worth a Sentry report.
        if code != .permissionDenied {
            CrashReporting.record(error, action: "submit report")
        }
        return code == .permissionDenied
            ? String(localized: "Your report was refused. Make sure your email is verified, and wait a minute between reports.")
            : String(localized: "Check your connection and try again.")
    }

    // Reports store their address when filed; older ones are looked up once
    // and cached so the lists don't geocode on every redraw.
    func address(for report: Report) async -> String? {
        if let address = report.address ?? addressCache[report.id] {
            return address
        }
        let address = await Self.lookUpAddress(for: report.coordinate)
        addressCache[report.id] = address
        return address
    }

    // Street and area for a coordinate, e.g. "Piața Marii Adunări Naționale, Buiucani".
    static func lookUpAddress(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = (try? await request.mapItems)?.first else {
            return nil
        }
        // shortAddress often drops the street (just "Buiucani"), so prefer
        // the single-line full address without the country.
        return item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? item.address?.fullAddress
    }

    // Cached so reopening a report or scrolling the dashboard doesn't
    // re-download the same photo.
    func photo(for reportID: String) async -> UIImage? {
        if let cached = photoCache.object(forKey: reportID as NSString) {
            return cached
        }
        guard let snapshot = try? await photosCollection.document(reportID).getDocument(),
              let data = snapshot.data()?["data"] as? Data,
              let image = UIImage(data: data) else {
            return nil
        }
        photoCache.setObject(image, forKey: reportID as NSString)
        return image
    }

    // A second tap removes the upvote, so each user counts at most once.
    func toggleUpvote(_ report: Report) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let change = report.isUpvoted(by: uid)
            ? FieldValue.arrayRemove([uid])
            : FieldValue.arrayUnion([uid])
        reportsCollection.document(report.id).updateData(["upvoterIds": change], completion: failureHandler(String(localized: "Couldn't update your upvote.")))
    }

    // firestore.rules only lets staff change a report's status. Each change
    // is also appended to statusHistory so everyone can see when it happened.
    // (Firestore can't put serverTimestamp() inside an array, hence the
    // device time.)
    func updateStatus(_ report: Report, to status: ReportStatus) {
        guard status != report.status else { return }
        let entry: [String: Any] = ["status": status.rawValue, "date": Timestamp(date: Date())]
        reportsCollection.document(report.id).updateData([
            "status": status.rawValue,
            "statusHistory": FieldValue.arrayUnion([entry])
        ], completion: failureHandler(String(localized: "Couldn't change the status.")))
    }

    // A note from staff that everyone can read, e.g. "Crew booked for Monday".
    // An empty note removes it.
    func updateStaffNote(_ report: Report, to note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Any = trimmed.isEmpty ? FieldValue.delete() : trimmed
        reportsCollection.document(report.id).updateData(["staffNote": value], completion: failureHandler(String(localized: "Couldn't save the note.")))
    }

    // The reporter may fix their own report while it's still "reported".
    func updateReport(_ report: Report, category: ReportCategory, description: String) {
        reportsCollection.document(report.id).updateData([
            "category": category.rawValue,
            "description": Self.cleanedDescription(description)
        ], completion: failureHandler(String(localized: "Couldn't save your changes.")))
    }

    // A description is saved without the spaces and blank lines around it,
    // both for new reports and edits. The forms use the same check to keep
    // Submit and Save off while only whitespace is typed.
    static func cleanedDescription(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Staff can delete any report; reporters can withdraw their own. The
    // report and its photo doc go in one batch so a photo is never left
    // behind without its report.
    func deleteReport(_ report: Report) {
        let batch = db.batch()
        batch.deleteDocument(reportsCollection.document(report.id))
        batch.deleteDocument(photosCollection.document(report.id))
        let onFailure = failureHandler(String(localized: "Couldn't delete the report."))
        batch.commit { [weak self] error in
            if error == nil {
                self?.photoCache.removeObject(forKey: report.id as NSString)
            }
            onFailure(error)
        }
    }

    // Shows actionError (ContentView presents it as an alert) when a write
    // is rejected, instead of failing silently.
    private func failureHandler(_ message: String, action: String = #function) -> (Error?) -> Void {
        { [weak self] error in
            guard let error else { return }
            print("\(message) \(error.localizedDescription)")
            CrashReporting.record(error, action: action)
            let code = FirestoreErrorCode.Code(rawValue: (error as NSError).code)
            let reason = switch code {
            case .permissionDenied: String(localized: "You don't have permission to do that.")
            case .unavailable, .deadlineExceeded: String(localized: "Check your connection and try again.")
            default: String(localized: "Please try again.")
            }
            self?.actionError = "\(message) \(reason)"
        }
    }

    // Firestore docs max out at 1 MiB, so shrink to 1280px on the long side
    // and lower JPEG quality until the photo fits under maxPhotoBytes
    // (the same limit firestore.rules enforces).
    static func compressedJPEG(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1280
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longest)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        for quality in stride(from: 0.8, through: 0.2, by: -0.15) {
            if let data = resized.jpegData(compressionQuality: quality), data.count < maxPhotoBytes {
                return data
            }
        }
        return nil
    }

    static func report(id: String, data: [String: Any]) -> Report? {
        guard let categoryRaw = data["category"] as? String,
              let category = ReportCategory(rawValue: categoryRaw),
              let description = data["description"] as? String,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double,
              let statusRaw = data["status"] as? String,
              let status = ReportStatus(rawValue: statusRaw),
              let reporterId = data["reporterId"] as? String else {
            return nil
        }
        return Report(
            id: id,
            category: category,
            description: description,
            hasPhoto: data["hasPhoto"] as? Bool ?? false,
            address: data["address"] as? String,
            latitude: latitude,
            longitude: longitude,
            status: status,
            upvoterIds: data["upvoterIds"] as? [String] ?? [],
            reporterId: reporterId,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            staffNote: data["staffNote"] as? String,
            statusHistory: (data["statusHistory"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let raw = entry["status"] as? String,
                      let status = ReportStatus(rawValue: raw),
                      let date = (entry["date"] as? Timestamp)?.dateValue() else { return nil }
                return StatusChange(status: status, date: date)
            }
        )
    }
}
