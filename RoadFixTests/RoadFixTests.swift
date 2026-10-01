//
//  RoadFixTests.swift
//  RoadFixTests
//

import Testing
import UIKit
import CoreLocation
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
