//
//  ConnectionMonitor.swift
//  RoadFix
//

import Foundation
import Network

/// Tells whether the phone has a network connection right now.
///
/// Firestore keeps writes made offline and sends them later, but only calls
/// back once the server confirms, so ReportService checks this to tell the
/// user straight away that a report is waiting to be sent.
final class ConnectionMonitor {
    // True until the first update arrives, so a slow start never blocks a
    // write; ReportService also has a timeout for that case.
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = isOnline
            }
        }
        monitor.start(queue: DispatchQueue(label: "md.roadfix.connection-monitor"))
    }

    deinit {
        monitor.cancel()
    }
}
