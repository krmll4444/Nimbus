import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onFinished: () -> Void
    @State private var legalDocument: LegalDocuments?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image("NimbusMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.t(.onboardingTitle))
                        .font(.title2.weight(.semibold))
                    Text(settings.t(.onboardingSubtitle))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                onboardingPoint(
                    icon: "doc.on.clipboard",
                    title: settings.t(.onboardingClipboardTitle),
                    body: settings.t(.onboardingClipboardBody)
                )
                onboardingPoint(
                    icon: "accessibility",
                    title: settings.t(.onboardingAccessibilityTitle),
                    body: settings.t(.onboardingAccessibilityBody)
                )
                onboardingPoint(
                    icon: "lock.shield",
                    title: settings.t(.onboardingLocalTitle),
                    body: settings.t(.onboardingLocalBody)
                )
            }

            if !PasteService.isTrusted {
                Button {
                    PasteService.requestAccess()
                } label: {
                    Label(settings.t(.accessibilityNeeded), systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Label(settings.t(.accessibilityGranted), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(settings.t(.privacyPolicy)) {
                    legalDocument = .privacy
                }
                .buttonStyle(.link)

                Button(settings.t(.termsOfUse)) {
                    legalDocument = .terms
                }
                .buttonStyle(.link)

                Spacer()

                Button(settings.t(.onboardingContinue)) {
                    settings.hasCompletedOnboarding = true
                    onFinished()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document, settings: settings) {
                legalDocument = nil
            }
            .frame(width: 520, height: 480)
        }
    }

    private func onboardingPoint(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
