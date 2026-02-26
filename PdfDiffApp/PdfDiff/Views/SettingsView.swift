import SwiftUI

struct SettingsView: View {
    @State var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section("AI Analysis") {
                SecureField("OpenRouter API Key", text: Binding(
                    get: { settingsManager.apiKey },
                    set: { settingsManager.saveAPIKey($0) }
                ))
                .textFieldStyle(.roundedBorder)

                HStack {
                    statusIndicator
                    Spacer()
                    Button("Verify") {
                        Task { await settingsManager.verifyAPIKey() }
                    }
                    .disabled(!settingsManager.hasAPIKey || settingsManager.isVerifying)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch settingsManager.apiKeyStatus {
        case .unconfigured:
            Label("No API key configured", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .unverified:
            Label("Not verified", systemImage: "questionmark.circle")
                .foregroundStyle(.orange)
        case .valid:
            Label("Valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid:
            Label("Invalid key", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
