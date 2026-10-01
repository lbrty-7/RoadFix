import SwiftUI

struct ReportDetailView: View {
    let reportID: String
    @ObservedObject var reportService: ReportService
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var confirmWithdraw = false

    // Looked up live (not captured as a copy) so upvotes and status changes
    // show up while the sheet is open.
    private var report: Report? {
        reportService.reports.first { $0.id == reportID }
    }

    private var isStaff: Bool { authViewModel.currentUser?.isStaff == true }

    // Reporters can change their mind only until staff pick the report up.
    private var canEdit: Bool {
        guard let report else { return false }
        return report.reporterId == authViewModel.currentUser?.id && report.status == .reported
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
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Options", systemImage: "ellipsis.circle") {
                            Button("Edit Report", systemImage: "pencil") { showEdit = true }
                            Button("Withdraw Report", systemImage: "trash", role: .destructive) {
                                confirmWithdraw = true
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                if let report {
                    EditReportView(report: report, reportService: reportService)
                }
            }
            .confirmationDialog("Withdraw this report?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
                Button("Withdraw Report", role: .destructive) {
                    if let report {
                        reportService.deleteReport(report)
                        dismiss()
                    }
                }
            } message: {
                Text("It will be removed from the map for everyone.")
            }
        }
        .reportActionErrorAlert(reportService)
        // Opening the report counts as seeing its latest status.
        .onAppear { if let report { reportService.markSeen(report) } }
        .onChange(of: report?.status) { if let report { reportService.markSeen(report) } }
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

                Button {
                    reportService.toggleUpvote(report)
                } label: {
                    Label(
                        upvoted ? "Upvoted (\(report.upvoteCount))" : "Upvote (\(report.upvoteCount))",
                        systemImage: upvoted ? "hand.thumbsup.fill" : "hand.thumbsup"
                    )
                }
                .buttonStyle(.borderedProminent)

                if isStaff {
                    StaffNoteEditor(report: report, reportService: reportService)
                } else if let note = report.staffNote {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Note from Staff", systemImage: "text.bubble")
                            .font(.subheadline.bold())
                        Text(note)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                }

                StatusTimeline(report: report)
            }
            .padding()
        }
    }
}

/// Filing date followed by every status change staff have made.
private struct StatusTimeline: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.subheadline.bold())
            row(title: ReportStatus.reported.title, date: report.createdAt, color: ReportStatus.reported.color)
            ForEach(report.statusHistory, id: \.self) { change in
                row(title: change.status.title, date: change.date, color: change.status.color)
            }
        }
    }

    private func row(title: String, date: Date, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Lets staff write the public note shown to citizens on this report.
private struct StaffNoteEditor: View {
    let report: Report
    @ObservedObject var reportService: ReportService
    @State private var note = ""

    private var hasChanges: Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines) != (report.staffNote ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Note for Citizens", systemImage: "text.bubble")
                .font(.subheadline.bold())
            TextField("e.g. Repair crew booked for Monday", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            Button("Save Note") {
                reportService.updateStaffNote(report, to: note)
            }
            .buttonStyle(.bordered)
            .disabled(!hasChanges)
        }
        .onAppear { note = report.staffNote ?? "" }
    }
}

/// Reporter's edit form for their own report's category and description.
private struct EditReportView: View {
    let report: Report
    @ObservedObject var reportService: ReportService
    @Environment(\.dismiss) private var dismiss

    @State private var category: ReportCategory
    @State private var description: String

    init(report: Report, reportService: ReportService) {
        self.report = report
        self.reportService = reportService
        _category = State(initialValue: report.category)
        _description = State(initialValue: report.description)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(ReportCategory.allCases) { cat in
                            Label(cat.title, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }
                Section("Description") {
                    TextField("What's the issue?", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        reportService.updateReport(report, category: category, description: trimmedDescription)
                        dismiss()
                    }
                    .disabled(trimmedDescription.isEmpty)
                }
            }
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
        return String(localized: "Finding address…")
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

// Shows ReportService.actionError. Attached to ContentView and to the report
// sheets, since an alert can't appear from a view that's behind a sheet.
struct ReportActionErrorAlert: ViewModifier {
    @ObservedObject var reportService: ReportService

    func body(content: Content) -> some View {
        content.alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { reportService.actionError != nil },
                set: { if !$0 { reportService.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportService.actionError ?? "")
        }
    }
}

extension View {
    func reportActionErrorAlert(_ reportService: ReportService) -> some View {
        modifier(ReportActionErrorAlert(reportService: reportService))
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
