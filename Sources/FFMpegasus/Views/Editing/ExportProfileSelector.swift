import FFMpegasusCore
import SwiftUI

struct ExportProfileSelector: View {
    @Binding var selectedProfile: ExportProfile
    let capabilities: ExportProfileCapabilities?
    let capabilityMessage: String?
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Output Format", selection: $selectedProfile) {
                ForEach(ExportProfile.allCases) { profile in
                    Text(profile.displayName)
                        .tag(profile)
                        .disabled(capabilities?.support(for: profile).isSupported == false)
                }
            }
            .pickerStyle(.menu)
            .disabled(disabled)
            .accessibilityIdentifier("exportProfile.selector")

            Text(selectedProfile.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("exportProfile.summary")

            if selectedProfile.isLargeOutputProfile {
                Text("This profile creates large files for editing workflows.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("exportProfile.largeFileWarning")
            }

            if let capabilities {
                if let explanation = capabilities.support(for: selectedProfile).explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("exportProfile.unsupportedMessage")
                }
            } else if let capabilityMessage {
                Text("Encoder support unavailable: \(capabilityMessage)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("exportProfile.unsupportedMessage")
            }
        }
    }
}

extension ExportProfile {
    var contentTypeIdentifier: String {
        switch self {
        case .mp4H264, .mp4HEVC:
            "public.mpeg-4"
        case .webmVP9:
            "org.webmproject.webm"
        case .movProRes422:
            "com.apple.quicktime-movie"
        }
    }
}
