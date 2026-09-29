import SwiftUI

struct StaffDashboardView: View {
    @ObservedObject var reportService: ReportService
    @State private var selectedReport: Report?

    var body: some View {
        List(reportService.reports) { report in
            VStack(alignment: .leading, spacing: 6) {
                // Borderless so only this part opens the report; otherwise the
                // whole row (including the status picker) would act as one button.
                Button {
                    selectedReport = report
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if report.hasPhoto {
                            ReportPhotoView(reportID: report.id, reportService: reportService)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(report.category.title, systemImage: report.category.systemImage)
                                    .font(.subheadline.bold())
                                Spacer()
                                StatusBadge(status: report.status)
                            }

                            ReportAddressView(report: report, reportService: reportService)
                                .font(.caption)
                                .lineLimit(1)

                            Text(report.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)

                Picker("Status", selection: Binding(
                    get: { report.status },
                    set: { newStatus in reportService.updateStatus(report, to: newStatus) }
                )) {
                    ForEach(ReportStatus.allCases, id: \.self) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
        }
        .sheet(item: $selectedReport) { report in
            ReportDetailView(reportID: report.id, reportService: reportService)
        }
    }
}
