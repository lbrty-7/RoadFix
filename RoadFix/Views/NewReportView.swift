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

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        if let selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                        } else {
                            Label("Add a photo", systemImage: "camera.fill")
                        }
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
                        Label(pinAddress ?? "Finding address…", systemImage: "mappin.and.ellipse")
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
                submitError = "Check your connection and try again."
            }
        }
    }
}
