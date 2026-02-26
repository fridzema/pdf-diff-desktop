import Foundation

@Observable @MainActor
final class SettingsManager {
    enum APIKeyStatus: String {
        case unconfigured
        case unverified
        case valid
        case invalid
    }

    private(set) var apiKeyStatus: APIKeyStatus = .unconfigured
    var apiKey: String = ""
    var isVerifying = false

    private let keychainHelper: KeychainHelper
    private let keychainKey = "openrouter_api_key"

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    init(keychainHelper: KeychainHelper = KeychainHelper()) {
        self.keychainHelper = keychainHelper
        // Load saved key on init
        if let saved = try? keychainHelper.read(key: keychainKey), !saved.isEmpty {
            self.apiKey = saved
            self.apiKeyStatus = .unverified
        }
    }

    func saveAPIKey(_ key: String) {
        apiKey = key
        if key.isEmpty {
            apiKeyStatus = .unconfigured
            try? keychainHelper.delete(key: keychainKey)
        } else {
            apiKeyStatus = .unverified
            try? keychainHelper.save(key: keychainKey, value: key)
        }
    }

    func verifyAPIKey() async {
        guard hasAPIKey else { return }
        isVerifying = true
        defer { isVerifying = false }

        // Lightweight call to OpenRouter to check the key
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                apiKeyStatus = .valid
            } else {
                apiKeyStatus = .invalid
            }
        } catch {
            apiKeyStatus = .invalid
        }
    }
}
