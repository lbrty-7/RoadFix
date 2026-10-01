import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined

    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return String(localized: "While Using the App")
        case .denied: return String(localized: "Off")
        case .restricted: return String(localized: "Restricted")
        case .notDetermined: return String(localized: "Not Asked Yet")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: authViewModel.currentUser?.email ?? "")
                LabeledContent("Role", value: authViewModel.currentUser?.isStaff == true ? "Staff" : "Citizen")
                NavigationLink("Change Password") {
                    ChangePasswordView()
                }
            }

            Section {
                LabeledContent("Location Access", value: locationStatusText)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("RoadFix only uses your location while the app is open, to pin new reports and show where you are on the map.")
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
            }

            Section {
                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Text("Delete Account")
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear(perform: refreshLocationStatus)
        .onChange(of: scenePhase) { _, phase in
            // Pick up changes made in the iOS Settings app.
            if phase == .active { refreshLocationStatus() }
        }
    }

    private func refreshLocationStatus() {
        locationStatus = CLLocationManager().authorizationStatus
    }
}
