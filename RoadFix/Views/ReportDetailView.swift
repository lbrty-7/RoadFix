import SwiftUI

struct ReportDetailView: View {
    let reportID: String
    @ObservedObject var reportService: ReportService
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // Looked up live (not captured as a copy) so upvotes and status changes
    // show up while the sheet is open.
    private var report: Report? {
        reportService.reports.first { $0.id == reportID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    details(for: report)
                } else {
                    ContentUnavailableView("Report Unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Report Detail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func details(for report: Report) -> some View {
        let upvoted = report.isUpvoted(by: authViewModel.currentUser?.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if report.hasPhoto {
                    ReportPhotoView(reportID: report.id, reportService: reportService)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Label(report.category.title, systemImage: report.category.systemImage)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: report.status)
                }

                ReportAddressView(report: report, reportService: reportService)
                    .font(.subheadline)

                Text(report.description)
                    .font(.body)

                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    reportService.toggleUpvote(report)
                } label: {
                    Label(
                        upvoted ? "Upvoted (\(report.upvoteCount))" : "Upvote (\(report.upvoteCount))",
                        systemImage: upvoted ? "hand.thumbsup.fill" : "hand.thumbsup"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

// Loads a report's photo from reportPhotos/{id}. Used by both the report
// detail sheet and the staff dashboard; size it with .frame at the call site.
struct ReportPhotoView: View {
    let reportID: String
    @ObservedObject var reportService: ReportService

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: reportID) {
            image = await reportService.photo(for: reportID)
            failed = image == nil
        }
    }
}

// Street and city of a report, shown on every report for staff and citizens.
// Falls back to coordinates if the address can't be looked up.
struct ReportAddressView: View {
    let report: Report
    @ObservedObject var reportService: ReportService

    @State private var address: String?
    @State private var lookupFinished = false

    private var text: String {
        if let address = address ?? report.address {
            return address
        }
        if lookupFinished {
            return String(format: "%.5f, %.5f", report.latitude, report.longitude)
        }
        return "Finding address…"
    }

    var body: some View {
        Label(text, systemImage: "mappin.and.ellipse")
            .task(id: report.id) {
                address = await reportService.address(for: report)
                lookupFinished = true
            }
    }
}

struct StatusBadge: View {
    let status: ReportStatus

    var body: some View {
        Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

extension ReportStatus {
    var color: Color {
        switch self {
        case .reported: return .red
        case .inProgress: return .orange
        case .resolved: return .green
        }
    }
}
