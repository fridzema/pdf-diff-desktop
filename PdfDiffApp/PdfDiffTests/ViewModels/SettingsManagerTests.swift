import Testing
import Foundation
@testable import PdfDiff

@Suite("SettingsManager Tests")
@MainActor
struct SettingsManagerTests {
    @Test("initially has no API key")
    func initiallyNoKey() {
        let manager = SettingsManager(keychainHelper: KeychainHelper(service: "com.pdfdiff.test.\(UUID().uuidString)"))
        #expect(manager.apiKey.isEmpty)
        #expect(manager.apiKeyStatus == .unconfigured)
    }

    @Test("saving API key updates status")
    func savingKeyUpdatesStatus() {
        let manager = SettingsManager(keychainHelper: KeychainHelper(service: "com.pdfdiff.test.\(UUID().uuidString)"))
        manager.saveAPIKey("sk-or-v1-test123")
        #expect(manager.apiKey == "sk-or-v1-test123")
        #expect(manager.apiKeyStatus == .unverified)
    }

    @Test("saving empty key resets to unconfigured")
    func emptyKeyResetsStatus() {
        let manager = SettingsManager(keychainHelper: KeychainHelper(service: "com.pdfdiff.test.\(UUID().uuidString)"))
        manager.saveAPIKey("sk-or-v1-test123")
        manager.saveAPIKey("")
        #expect(manager.apiKeyStatus == .unconfigured)
    }

    @Test("hasValidAPIKey is false when unconfigured")
    func hasValidKeyFalseWhenUnconfigured() {
        let manager = SettingsManager(keychainHelper: KeychainHelper(service: "com.pdfdiff.test.\(UUID().uuidString)"))
        #expect(!manager.hasAPIKey)
    }

    @Test("hasAPIKey is true when key is saved")
    func hasKeyTrueWhenSaved() {
        let manager = SettingsManager(keychainHelper: KeychainHelper(service: "com.pdfdiff.test.\(UUID().uuidString)"))
        manager.saveAPIKey("sk-or-v1-test123")
        #expect(manager.hasAPIKey)
    }
}
