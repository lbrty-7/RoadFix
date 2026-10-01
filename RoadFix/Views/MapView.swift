import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var reportService: ReportService
    @Binding var showingNewReport: Bool
    @StateObject private var locationManager = LocationManager()
    @State private var selectedReport: Report?
    @State private var cameraPosition: MapCameraPosition = .automatic
    // Resolved issues are hidden by default so the map shows what's still open.
    @State private var visibleStatuses: Set<ReportStatus> = [.reported, .inProgress]
    @State private var visibleCategories = Set(ReportCategory.allCases)

    private var visibleReports: [Report] {
        reportService.reports.filter { visibleStatuses.contains($0.status) && visibleCategories.contains($0.category) }
    }

    private var isFiltered: Bool {
        visibleStatuses != [.reported, .inProgress] || visibleCategories.count != ReportCategory.allCases.count
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(visibleReports) { report in
                    Annotation(report.category.title, coordinate: report.coordinate) {
                        Button {
                            selectedReport = report
                        } label: {
                            Image(systemName: report.category.systemImage)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(report.status.color)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("\(report.category.title), \(report.status.title)")
                    }
                }
            }
            // Draw the map under the title bar instead of stopping below it.
            .ignoresSafeArea(edges: .top)
            .sheet(item: $selectedReport) { report in
                ReportDetailView(reportID: report.id, reportService: reportService)
            }

            VStack(spacing: 12) {
                filterMenu

                Button {
                    // Asks for permission the first time; the camera then
                    // follows the user once a location comes in.
                    locationManager.requestLocation()
                    withAnimation {
                        cameraPosition = .userLocation(fallback: .automatic)
                    }
                } label: {
                    mapButtonIcon("location.fill")
                }
                .accessibilityLabel("Show My Location")

                Button {
                    showingNewReport = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .accessibilityLabel("New Report")
            }
            .padding()
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Status") {
                ForEach(ReportStatus.allCases, id: \.self) { status in
                    Toggle(status.title, isOn: binding(for: status, in: $visibleStatuses))
                }
            }
            Section("Category") {
                ForEach(ReportCategory.allCases) { category in
                    Toggle(isOn: binding(for: category, in: $visibleCategories)) {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
            }
            if isFiltered {
                Button("Reset Filters", systemImage: "arrow.counterclockwise") {
                    visibleStatuses = [.reported, .inProgress]
                    visibleCategories = Set(ReportCategory.allCases)
                }
            }
        } label: {
            mapButtonIcon(isFiltered
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease")
        }
        // Keep the menu open while toggling several options.
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel("Filter Reports")
    }

    private func mapButtonIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    private func binding<Value: Hashable>(for value: Value, in set: Binding<Set<Value>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
            }
        )
    }
}
