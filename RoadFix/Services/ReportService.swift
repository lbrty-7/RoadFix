import Foundation
import CoreLocation
import MapKit
import UIKit
import Combine
import FirebaseAuth
import FirebaseFirestore

class ReportService: ObservableObject {
    @Published var reports: [Report] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let photoCache = NSCache<NSString, UIImage>()
    private var addressCache: [String: String] = [:]
    private static let maxPhotoBytes = 900 * 1024

    private var reportsCollection: CollectionReference {
        db.collection("reports")
    }

    private var photosCollection: CollectionReference {
        db.collection("reportPhotos")
    }

    // Live-syncs every report so the map, dashboard and "My Reports" update
    // as soon as anyone submits, upvotes or changes a status.
    func startListening() {
        guard listener == nil else { return }
        listener = reportsCollection.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error { print("Reports listener error: \(error.localizedDescription)") }
                return
            }
            self.reports = documents
                .compactMap { Self.report(id: $0.documentID, data: $0.data(with: .estimate)) }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func submitReport(
        category: ReportCategory,
        description: String,
        image: UIImage?,
        coordinate: CLLocationCoordinate2D,
        address: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        let document = reportsCollection.document()
        let photoData = image.flatMap(Self.compressedJPEG)
        var data: [String: Any] = [
            "category": category.rawValue,
            "description": description,
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
        let batch = db.batch()
        batch.setData(data, forDocument: document)
        if let photoData {
            batch.setData(["data": photoData], forDocument: photosCollection.document(document.documentID))
        }
        batch.commit { error in
            if let error { print("Submit report error: \(error.localizedDescription)") }
            completion(error == nil)
        }
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
        reportsCollection.document(report.id).updateData(["upvoterIds": change])
    }

    // firestore.rules only lets staff change a report's status.
    func updateStatus(_ report: Report, to status: ReportStatus) {
        reportsCollection.document(report.id).updateData(["status": status.rawValue])
    }

    // Firestore docs max out at 1 MiB, so shrink to 1280px on the long side
    // and lower JPEG quality until the photo fits under maxPhotoBytes
    // (the same limit firestore.rules enforces).
    private static func compressedJPEG(_ image: UIImage) -> Data? {
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

    private static func report(id: String, data: [String: Any]) -> Report? {
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
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}
