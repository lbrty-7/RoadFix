import SwiftUI

struct StaffDashboardView: View {
    @ObservedObject var reportService: ReportService
    @State private var selectedReport: Report?
    @State private var reportToDelete: Report?
    @State private var searchText = ""
    @State private var sortOrder: ReportSortOrder = .newest
    // nil shows every status.
    @State private var statusFilter: ReportStatus?

    private var shownReports: [Report] {
        let filtered = reportService.reports.filter { report in
            (statusFilter == nil || report.status == statusFilter) && report.matches(search: searchText)
        }
        return sortOrder.sorted(filtered)
    }

    var body: some View {
        List(shownReports) { report in
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

                            HStack(spacing: 12) {
                                Label("\(report.upvoteCount)", systemImage: "hand.thumbsup.fill")
                                Text(report.createdAt.formatted(.relative(presentation: .named)))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    reportToDelete = report
                }
            }
        }
        .overlay {
            if shownReports.isEmpty {
                if reportService.reports.isEmpty {
                    ContentUnavailableView("No Reports Yet", systemImage: "tray")
                } else {
                    ContentUnavailableView.search
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search description or address")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(ReportSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    Picker("Status", selection: $statusFilter) {
                        Text("All Statuses").tag(ReportStatus?.none)
                        ForEach(ReportStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(Optional(status))
                        }
                    }
                } label: {
                    Label("Sort and Filter", systemImage: statusFilter == nil
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .sheet(item: $selectedReport) { report in
            ReportDetailView(reportID: report.id, reportService: reportService)
        }
        // Deleting can't be undone, so ask before removing the report.
        .alert(
            "Delete Report?",
            isPresented: Binding(
                get: { reportToDelete != nil },
                set: { if !$0 { reportToDelete = nil } }
            ),
            presenting: reportToDelete
        ) { report in
            Button("Delete", role: .destructive) {
                reportService.deleteReport(report)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes the report and its photo for everyone.")
        }
    }
}
