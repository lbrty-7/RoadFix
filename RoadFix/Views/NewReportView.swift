import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

struct NewReportView: View {
    @ObservedObject var reportService: ReportService
    @StateObject private var locationManager = LocationManager()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var category: ReportCategory = .pothole
    @State private var description: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showPhotoSourceDialog = false
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var isSubmitting = false
    @State private var submitError: String?
    // Where the report will be filed. Starts at the user's location and
    // follows it until they tap the map to choose a spot themselves.
    @State private var pinnedLocation: CLLocationCoordinate2D?
    @State private var pinFollowsCurrentLocation = true
    @State private var pinAddress: String?
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    private var locationDenied: Bool {
        locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted
    }

    // CLLocationCoordinate2D isn't Equatable, so onChange watches this instead.
    private var currentLocationKey: [Double]? {
        locationManager.currentLocation.map { [$0.latitude, $0.longitude] }
    }

    private var pinnedLocationKey: [Double]? {
        pinnedLocation.map { [$0.latitude, $0.longitude] }
    }

    @State private var duplicateToView: Report?

    private var possibleDuplicates: [Report] {
        guard let pinnedLocation else { return [] }
        return Report.possibleDuplicates(of: category, near: pinnedLocation, in: reportService.reports)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    Button {
                        showPhotoSourceDialog = true
                    } label: {
                        if let selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                        } else {
                            Label("Add a photo", systemImage: "camera.fill")
                        }
                    }
                    .confirmationDialog("Add a Photo", isPresented: $showPhotoSourceDialog, titleVisibility: .visible) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take Photo") { showCamera = true }
                        }
                        Button("Choose from Library") { showPhotoLibrary = true }
                        if selectedImage != nil {
                            Button("Remove Photo", role: .destructive) {
                                selectedImage = nil
                                selectedItem = nil
                            }
                        }
                    }
                    .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedItem, matching: .images)
                    .fullScreenCover(isPresented: $showCamera) {
                        CameraPicker(image: $selectedImage)
                            .ignoresSafeArea()
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                selectedImage = UIImage(data: data)
                            }
                        }
                    }
                }

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

                Section {
                    MapReader { proxy in
                        Map(position: $mapPosition) {
                            UserAnnotation()
                            if let pinnedLocation {
                                Marker("Issue", systemImage: category.systemImage, coordinate: pinnedLocation)
                            }
                        }
                        .onTapGesture { point in
                            if let coordinate = proxy.convert(point, from: .local) {
                                pinnedLocation = coordinate
                                pinFollowsCurrentLocation = false
                            }
                        }
                    }
                    .frame(height: 250)
                    .listRowInsets(EdgeInsets())

                    if pinnedLocation != nil {
                        Label(pinAddress ?? String(localized: "Finding address…"), systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            // Re-runs (and cancels the old lookup) each time the pin moves.
                            .task(id: pinnedLocationKey) {
                                pinAddress = nil
                                guard let pinnedLocation else { return }
                                pinAddress = await ReportService.lookUpAddress(for: pinnedLocation)
                            }
                    }

                    Button {
                        useCurrentLocation()
                    } label: {
                        Label("Use My Current Location", systemImage: "location.fill")
                    }
                    .disabled(locationDenied)

                    if locationDenied {
                        Text("Location access is turned off. You can still tap the map to pin the issue.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    } else if pinnedLocation == nil {
                        Text("Fetching current location…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Tap the map to move the pin to where the issue is.")
                }

                if let pinnedLocation, !possibleDuplicates.isEmpty {
                    Section {
                        ForEach(possibleDuplicates.prefix(3)) { report in
                            Button {
                                duplicateToView = report
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(report.description)
                                            .lineLimit(2)
                                        Text("\(Int(report.distance(to: pinnedLocation))) m away · \(report.upvoteCount) upvotes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    StatusBadge(status: report.status)
                                }
                            }
                            .tint(.primary)
                        }
                    } header: {
                        Label("Already Reported Nearby?", systemImage: "exclamationmark.bubble")
                    } footer: {
                        Text("If one of these is the same issue, upvote it instead of filing a new report. Upvotes help staff see which issues matter most.")
                    }
                }
            }
            .sheet(item: $duplicateToView) { report in
                ReportDetailView(reportID: report.id, reportService: reportService)
            }
            .navigationTitle("New Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting…" : "Submit") {
                        submit()
                    }
                    .disabled(description.isEmpty || pinnedLocation == nil || isSubmitting)
                }
            }
            .onAppear {
                locationManager.requestLocation()
            }
            .onChange(of: currentLocationKey) {
                guard pinFollowsCurrentLocation, let current = locationManager.currentLocation else { return }
                movePin(to: current)
            }
            .alert("Couldn't Submit Report", isPresented: Binding(
                get: { submitError != nil },
                set: { if !$0 { submitError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(submitError ?? "")
            }
        }
    }

    private func useCurrentLocation() {
        pinFollowsCurrentLocation = true
        if let current = locationManager.currentLocation {
            movePin(to: current)
        }
        // Refresh in case the user has moved; onChange moves the pin again.
        locationManager.requestLocation()
    }

    private func movePin(to coordinate: CLLocationCoordinate2D) {
        pinnedLocation = coordinate
        withAnimation {
            mapPosition = .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))
        }
    }

    private func submit() {
        guard let coordinate = pinnedLocation else { return }
        isSubmitting = true
        reportService.submitReport(
            category: category,
            description: description,
            image: selectedImage,
            coordinate: coordinate,
            address: pinAddress
        ) { success in
            isSubmitting = false
            if success {
                dismiss()
            } else {
                submitError = String(localized: "Check your connection and try again.")
            }
        }
    }
}

/// Wraps UIImagePickerController so the user can take a photo with the camera,
/// since SwiftUI's PhotosPicker only reads from the photo library.
private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
