import SwiftUI

/// The privacy policy and terms of use, shown from sign-up and Settings.
/// They describe what the app actually stores (see ReportService and
/// AuthViewModel), so update them whenever that changes.
enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return String(localized: "Privacy Policy")
        case .terms: return String(localized: "Terms of Use")
        }
    }

    static let lastUpdated = DateComponents(calendar: .current, year: 2026, month: 11, day: 6).date ?? .now

    struct Section: Identifiable {
        let heading: String
        let body: String
        var id: String { heading }
    }

    var sections: [Section] {
        switch self {
        case .privacy:
            return [
                Section(
                    heading: String(localized: "Who we are"),
                    body: String(localized: "RoadFix lets residents report road problems such as potholes and broken streetlights so city staff can fix them. RoadFix is run from the Republic of Moldova. You can reach us through the support contact on the RoadFix App Store page.")
                ),
                Section(
                    heading: String(localized: "What we collect"),
                    body: String(localized: "Your email address and password, used only to sign you in. Your password is handled by Firebase Authentication and we never see it. Your account role (citizen or staff) and the dates you created your account and accepted these terms. For each report you send: the category, your description, the location and street address, an optional photo and the time. When you upvote a report, your account ID is added to it so you can only upvote once.")
                ),
                Section(
                    heading: String(localized: "Location"),
                    body: String(localized: "RoadFix uses your location only while the app is open, to pin new reports and show where you are on the map. A location is saved only when you send a report, and only the spot you pinned.")
                ),
                Section(
                    heading: String(localized: "Who can see your reports"),
                    body: String(localized: "Reports, including their photo, description and location, are visible to everyone signed in to RoadFix and to city staff. Your email address is never shown to other users. Don't include faces, license plates or other personal details in photos or descriptions.")
                ),
                Section(
                    heading: String(localized: "Why we use your data"),
                    body: String(localized: "To run the service you signed up for: sending reports to city staff and showing their progress. And to keep the service safe, for example by limiting how often reports can be sent. We don't show ads, we don't use analytics or tracking, and we never sell your data.")
                ),
                Section(
                    heading: String(localized: "Services we rely on"),
                    body: String(localized: "Accounts and reports are stored with Google Firebase (Firebase Authentication and Cloud Firestore). Maps and street addresses come from Apple Maps. These providers may process data outside Moldova and the EU under their own data protection terms.")
                ),
                Section(
                    heading: String(localized: "How long we keep it"),
                    body: String(localized: "Until you delete it. You can withdraw any of your reports, and Settings > Delete Account removes your account, all your reports and their photos straight away.")
                ),
                Section(
                    heading: String(localized: "Your rights"),
                    body: String(localized: "You can ask for a copy of your data, ask us to correct or delete it, or object to how we use it. You can also complain to the National Center for Personal Data Protection of Moldova (CNPDCP) or, in the EU, to your local data protection authority.")
                ),
                Section(
                    heading: String(localized: "Children"),
                    body: String(localized: "RoadFix is for people aged 16 and over. We don't knowingly collect data from children, and we delete any account we learn belongs to a child under 16.")
                ),
                Section(
                    heading: String(localized: "Changes"),
                    body: String(localized: "If this policy changes, we'll update the date below and tell you in the app before the change takes effect.")
                )
            ]
        case .terms:
            return [
                Section(
                    heading: String(localized: "Using RoadFix"),
                    body: String(localized: "RoadFix is for reporting real problems on public roads, sidewalks and streetlights. You must be 16 or older to create an account.")
                ),
                Section(
                    heading: String(localized: "Not for emergencies"),
                    body: String(localized: "RoadFix is not an emergency service. If something is dangerous right now, call 112.")
                ),
                Section(
                    heading: String(localized: "What you may not post"),
                    body: String(localized: "False or duplicate reports sent on purpose, offensive content, advertising, or other people's personal details such as faces or license plates. Staff may remove reports that break these rules, and we may suspend accounts that keep breaking them.")
                ),
                Section(
                    heading: String(localized: "Your photos and text"),
                    body: String(localized: "You keep the rights to what you post. By sending a report you allow RoadFix and city staff to show it in the app so the problem can be handled.")
                ),
                Section(
                    heading: String(localized: "No guarantee of repairs"),
                    body: String(localized: "City staff decide when and whether a reported problem is fixed. A status in the app is information, not a promise.")
                ),
                Section(
                    heading: String(localized: "Your account"),
                    body: String(localized: "Keep your password private. You can delete your account at any time in Settings.")
                ),
                Section(
                    heading: String(localized: "Liability and law"),
                    body: String(localized: "RoadFix is provided as it is, and we are not liable for damage caused by road conditions or by delays in repairs, as far as the law allows. These terms are governed by the laws of the Republic of Moldova.")
                )
            ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.heading)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.body)
                    }
                }
                Text("Last updated \(LegalDocument.lastUpdated.formatted(date: .long, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(document: .privacy)
    }
}
