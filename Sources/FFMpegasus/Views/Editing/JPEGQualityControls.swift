import FFMpegasusCore
import SwiftUI

struct JPEGQualityControls: View {
    let isVisible: Bool
    let controlsDisabled: Bool
    @Binding var preset: JPEGQualityPreset
    @Binding var customQuality: Int

    var body: some View {
        if isVisible {
            Picker("JPEG Quality", selection: $preset) {
                ForEach(JPEGQualityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            if preset == .custom {
                Stepper("Quality \(customQuality)", value: $customQuality, in: JPEGQuality.validRange)
                    .disabled(controlsDisabled)
            }

            Text("Lower JPEG quality values produce higher-quality, larger images.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
