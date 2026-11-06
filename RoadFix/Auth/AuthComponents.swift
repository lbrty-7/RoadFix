//
//  AuthComponents.swift
//  RoadFix
//
//  Shared building blocks for LoginView and SignUpView: a blurred city-map
//  background, the app header, a solid field card and the primary button,
//  so both screens match the map-first look of the rest of the app.
//

import SwiftUI
import MapKit
import CoreLocation

enum AuthFocus: Hashable {
    case email, password, confirmPassword, staffCode
}

/// Scrollable, vertically centred container with the map background.
/// Scrolls when the keyboard is up or text is large.
struct AuthScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            AuthBackground()
        }
    }
}

/// Blurred, non-interactive map of Chișinău behind the auth forms.
struct AuthBackground: View {
    private static let chisinau = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.0245, longitude: 28.8322),
        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
    )

    var body: some View {
        Map(initialPosition: .region(Self.chisinau), interactionModes: [])
            .blur(radius: 8)
            .overlay(Color(.systemBackground).opacity(0.35))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
    }
}

struct AuthHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 18))
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Grouped rows on an opaque card, like the app's Settings rows. Opaque
/// rather than glass so the fields stay readable over the map.
struct AuthCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.separator))
        }
    }
}

struct AuthCardDivider: View {
    var body: some View {
        Divider().padding(.leading, 48)
    }
}

/// One field row: SF Symbol, text or secure field, and a show/hide button
/// for passwords. `contentType` lets iCloud Passwords autofill the field.
struct AuthField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var focus: FocusState<AuthFocus?>.Binding
    let field: AuthFocus

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Group {
                if isSecure && !isRevealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .focused(focus, equals: field)

            if isSecure {
                Button {
                    isRevealed.toggle()
                    // Swapping SecureField/TextField drops focus; put it back.
                    focus.wrappedValue = field
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }
}

struct AuthErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}

/// Full-width filled button that shows a spinner while a request is running.
struct AuthPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .fontWeight(.semibold)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled || isLoading)
    }
}

/// A square checkbox for consent rows: the label wraps, and the whole row
/// is tappable. VoiceOver reads it as a toggle with its on/off value.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                configuration.label
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
