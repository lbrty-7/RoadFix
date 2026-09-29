import Foundation
import CoreLocation

// Raw values are the strings stored in Firestore; `title` is what the UI shows.
enum ReportCategory: String, CaseIterable, Identifiable, Hashable {
    case pothole
    case streetlight
    case sidewalk
    case markings
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pothole: return "Pothole"
        case .streetlight: return "Broken Streetlight"
        case .sidewalk: return "Damaged Sidewalk"
        case .markings: return "Faded Road Markings"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .pothole: return "exclamationmark.triangle.fill"
        case .streetlight: return "lightbulb.slash.fill"
        case .sidewalk: return "figure.walk"
        case .markings: return "road.lanes"
        case .other: return "questionmark.circle.fill"
        }
    }
}

// Raw values must match firestore.rules (a new report's status is "reported").
enum ReportStatus: String, CaseIterable, Hashable {
    case reported
    case inProgress
    case resolved

    var title: String {
        switch self {
        case .reported: return "Reported"
        case .inProgress: return "In Progress"
        case .resolved: return "Resolved"
        }
    }
}

struct Report: Identifiable, Equatable {
    let id: String            // Firestore document ID
    var category: ReportCategory
    var description: String
    var hasPhoto: Bool        // photo itself is in reportPhotos/{id}
    var address: String?      // street and city; nil on reports filed before this was saved
    var latitude: Double
    var longitude: Double
    var status: ReportStatus
    var upvoterIds: [String]  // one entry per user, so each user can upvote once
    var reporterId: String
    var createdAt: Date

    var upvoteCount: Int { upvoterIds.count }

    func isUpvoted(by uid: String?) -> Bool {
        guard let uid else { return false }
        return upvoterIds.contains(uid)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
