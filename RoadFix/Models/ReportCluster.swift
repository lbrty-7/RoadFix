//
//  ReportCluster.swift
//  RoadFix
//

import Foundation
import CoreLocation

/// Reports close together on the map, drawn as one pin with a count so
/// nearby pins don't overlap. A cluster of one is drawn as a normal pin.
struct ReportCluster: Identifiable {
    let reports: [Report] // never empty, sorted by id

    // The smallest report id, so a cluster keeps its id while the map moves.
    var id: String { reports[0].id }

    var coordinate: CLLocationCoordinate2D {
        let count = Double(reports.count)
        return CLLocationCoordinate2D(
            latitude: reports.map(\.latitude).reduce(0, +) / count,
            longitude: reports.map(\.longitude).reduce(0, +) / count
        )
    }

    /// Groups reports that fall in the same square of `cellSize` degrees.
    /// A cellSize of 0 or less keeps every report on its own.
    static func group(_ reports: [Report], cellSize: Double) -> [ReportCluster] {
        guard cellSize > 0 else {
            return reports.map { ReportCluster(reports: [$0]) }.sorted { $0.id < $1.id }
        }
        let cells = Dictionary(grouping: reports) { report in
            Cell(
                x: Int((report.longitude / cellSize).rounded(.down)),
                y: Int((report.latitude / cellSize).rounded(.down))
            )
        }
        return cells.values
            .map { ReportCluster(reports: $0.sorted { $0.id < $1.id }) }
            .sorted { $0.id < $1.id }
    }

    /// The cell size for a visible map height: about 12 cells top to bottom,
    /// roughly one pin each. Zoomed in to a few streets it returns 0, so
    /// every report shows on its own.
    static func cellSize(forLatitudeSpan latitudeDelta: Double) -> Double {
        let size = latitudeDelta / 12
        return size < 0.0005 ? 0 : size
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }
}
