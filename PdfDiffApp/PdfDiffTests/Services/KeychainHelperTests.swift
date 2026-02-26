import Testing
import Foundation
@testable import PdfDiff

@Suite("KeychainHelper Tests")
struct KeychainHelperTests {
    // Use a unique test-only service name to avoid polluting real keychain
    let testService = "com.pdfdiff.test.\(UUID().uuidString)"

    @Test("save and read a value")
    func saveAndRead() throws {
        let helper = KeychainHelper(service: testService)
        try helper.save(key: "api_key", value: "sk-test-123")
        let value = try helper.read(key: "api_key")
        #expect(value == "sk-test-123")
        // Clean up
        try? helper.delete(key: "api_key")
    }

    @Test("read returns nil for missing key")
    func readMissing() throws {
        let helper = KeychainHelper(service: testService)
        let value = try helper.read(key: "nonexistent")
        #expect(value == nil)
    }

    @Test("save overwrites existing value")
    func saveOverwrites() throws {
        let helper = KeychainHelper(service: testService)
        try helper.save(key: "api_key", value: "old-value")
        try helper.save(key: "api_key", value: "new-value")
        let value = try helper.read(key: "api_key")
        #expect(value == "new-value")
        try? helper.delete(key: "api_key")
    }

    @Test("delete removes value")
    func deleteRemoves() throws {
        let helper = KeychainHelper(service: testService)
        try helper.save(key: "api_key", value: "to-delete")
        try helper.delete(key: "api_key")
        let value = try helper.read(key: "api_key")
        #expect(value == nil)
    }
}
