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
        case .pothole: return String(localized: "Pothole")
        case .streetlight: return String(localized: "Broken Streetlight")
        case .sidewalk: return String(localized: "Damaged Sidewalk")
        case .markings: return String(localized: "Faded Road Markings")
        case .other: return String(localized: "Other")
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
        case .reported: return String(localized: "Reported")
        case .inProgress: return String(localized: "In Progress")
        case .resolved: return String(localized: "Resolved")
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
    var staffNote: String? = nil          // public note from staff
    var statusHistory: [StatusChange] = [] // oldest first; empty on older reports

    var upvoteCount: Int { upvoterIds.count }

    var isOpen: Bool { status != .resolved }

    func isUpvoted(by uid: String?) -> Bool {
        guard let uid else { return false }
        return upvoterIds.contains(uid)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

struct StatusChange: Hashable {
    let status: ReportStatus
    let date: Date
}

// MARK: - Finding, filtering and sorting reports

extension Report {
    /// Open reports of the same category close to `coordinate`, nearest
    /// first — likely the same issue, so NewReportView suggests upvoting them.
    static func possibleDuplicates(
        of category: ReportCategory,
        near coordinate: CLLocationCoordinate2D,
        in reports: [Report],
        within meters: CLLocationDistance = 50
    ) -> [Report] {
        reports
            .filter { $0.category == category && $0.isOpen && $0.distance(to: coordinate) <= meters }
            .sorted { $0.distance(to: coordinate) < $1.distance(to: coordinate) }
    }

    /// Case-insensitive match on the description, address or category.
    func matches(search text: String) -> Bool {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return description.localizedStandardContains(query)
            || (address?.localizedStandardContains(query) ?? false)
            || category.title.localizedStandardContains(query)
    }
}

enum ReportSortOrder: String, CaseIterable, Identifiable {
    case newest, oldest, mostUpvoted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return String(localized: "Newest First")
        case .oldest: return String(localized: "Oldest First")
        case .mostUpvoted: return String(localized: "Most Upvoted")
        }
    }

    func sorted(_ reports: [Report]) -> [Report] {
        switch self {
        case .newest:
            return reports.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return reports.sorted { $0.createdAt < $1.createdAt }
        case .mostUpvoted:
            // Ties go to the newer report.
            return reports.sorted {
                $0.upvoteCount != $1.upvoteCount ? $0.upvoteCount > $1.upvoteCount : $0.createdAt > $1.createdAt
            }
        }
    }
}
