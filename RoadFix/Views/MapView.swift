import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var reportService: ReportService
    @Binding var showingNewReport: Bool
    @State private var selectedReport: Report?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition) {
                ForEach(reportService.reports) { report in
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
                    }
                }
            }
            // Draw the map under the title bar instead of stopping below it.
            .ignoresSafeArea(edges: .top)
            .sheet(item: $selectedReport) { report in
                ReportDetailView(reportID: report.id, reportService: reportService)
            }

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
            .padding()
        }
    }
}
