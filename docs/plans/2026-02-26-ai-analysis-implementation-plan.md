# AI-Powered Analysis Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add OpenRouter-powered AI analysis to the compare view — visual change description, semantic text comparison, prepress QC checklist, and anomaly detection — triggered by a single button, with results in the diff summary panel.

**Architecture:** Swift-side networking via `URLSession`. New `AIAnalysisService` protocol + `OpenRouterAIService` implementation. `SettingsManager` for Keychain-stored API key. Results displayed as new `DisclosureGroup` sections in existing `DiffSummaryPanel`.

**Tech Stack:** SwiftUI, Swift Observation, URLSession, Security.framework (Keychain), Swift Testing

---

### Task 1: AI Analysis Types

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/AIAnalysisService.swift`
- Test: `PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift`

**Step 1: Write the types and protocol**

Create `AIAnalysisService.swift` with the data types and protocol:

```swift
import Foundation
import AppKit

enum QCStatus: String, Codable {
    case pass, warn, fail
}

struct QCCheckItem: Codable {
    let check: String
    let status: QCStatus
    let detail: String
}

struct AIAnalysisResult {
    let visualChanges: String
    let textComparison: String
    let qcChecklist: [QCCheckItem]
    let anomalies: String
}

protocol AIAnalysisServiceProtocol: Sendable {
    func analyze(
        left: NSImage, right: NSImage, diff: NSImage,
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) async throws -> AIAnalysisResult
}
```

**Step 2: Write a MockAIAnalysisService for testing**

In the same file, add:

```swift
final class MockAIAnalysisService: AIAnalysisServiceProtocol, @unchecked Sendable {
    var mockResult: AIAnalysisResult?
    var mockError: Error?
    var analyzeCallCount = 0

    func analyze(
        left: NSImage, right: NSImage, diff: NSImage,
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) async throws -> AIAnalysisResult {
        analyzeCallCount += 1
        if let error = mockError { throw error }
        return mockResult ?? AIAnalysisResult(
            visualChanges: "Mock visual changes",
            textComparison: "Mock text comparison",
            qcChecklist: [QCCheckItem(check: "Bleed", status: .pass, detail: "OK")],
            anomalies: "No issues found"
        )
    }
}
```

**Step 3: Write tests for the types**

Create `PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift`:

```swift
import Testing
@testable import PdfDiff

@Suite("AIAnalysisService Tests")
struct AIAnalysisServiceTests {
    @Test("QCStatus raw values match expected JSON strings")
    func qcStatusRawValues() {
        #expect(QCStatus.pass.rawValue == "pass")
        #expect(QCStatus.warn.rawValue == "warn")
        #expect(QCStatus.fail.rawValue == "fail")
    }

    @Test("QCCheckItem decodes from JSON")
    func qcCheckItemDecodes() throws {
        let json = """
        {"check": "Bleed", "status": "warn", "detail": "Bleed is 2mm, expected 3mm"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(QCCheckItem.self, from: json)
        #expect(item.check == "Bleed")
        #expect(item.status == .warn)
        #expect(item.detail == "Bleed is 2mm, expected 3mm")
    }

    @Test("MockAIAnalysisService returns default result")
    @MainActor
    func mockReturnsDefault() async throws {
        let mock = MockAIAnalysisService()
        let dummyImage = NSImage(size: NSSize(width: 10, height: 10))
        let diffResult = PDFDiffResult(similarityScore: 0.95, diffImage: nil, changedRegions: [], changedPixelCount: 500, totalPixelCount: 10000)
        let structuralDiff = PDFStructuralDiffResult(metadataChanges: [], textChanges: [], fontChanges: [], pageSizeChanges: [])

        let result = try await mock.analyze(
            left: dummyImage, right: dummyImage, diff: dummyImage,
            leftText: "hello", rightText: "world",
            diffResult: diffResult, structuralDiff: structuralDiff
        )
        #expect(result.visualChanges == "Mock visual changes")
        #expect(mock.analyzeCallCount == 1)
    }

    @Test("MockAIAnalysisService throws when configured")
    @MainActor
    func mockThrows() async {
        let mock = MockAIAnalysisService()
        mock.mockError = NSError(domain: "Test", code: 401)
        let dummyImage = NSImage(size: NSSize(width: 10, height: 10))
        let diffResult = PDFDiffResult(similarityScore: 0.95, diffImage: nil, changedRegions: [], changedPixelCount: 500, totalPixelCount: 10000)
        let structuralDiff = PDFStructuralDiffResult(metadataChanges: [], textChanges: [], fontChanges: [], pageSizeChanges: [])

        do {
            _ = try await mock.analyze(
                left: dummyImage, right: dummyImage, diff: dummyImage,
                leftText: "", rightText: "",
                diffResult: diffResult, structuralDiff: structuralDiff
            )
            Issue.record("Expected error")
        } catch {
            #expect((error as NSError).code == 401)
        }
    }
}
```

**Step 4: Regenerate Xcode project and run tests**

Run:
```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests PASS including the 4 new ones.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/AIAnalysisService.swift PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift
git commit -m "feat: add AIAnalysisService protocol, types, and mock"
```

---

### Task 2: Keychain Helper

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/KeychainHelper.swift`
- Test: `PdfDiffApp/PdfDiffTests/Services/KeychainHelperTests.swift`

**Step 1: Write tests for the Keychain helper**

Create `PdfDiffApp/PdfDiffTests/Services/KeychainHelperTests.swift`:

```swift
import Testing
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
```

**Step 2: Run tests to verify they fail**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL — `KeychainHelper` not found.

**Step 3: Implement KeychainHelper**

Create `PdfDiffApp/PdfDiff/Services/KeychainHelper.swift`:

```swift
import Foundation
import Security

struct KeychainHelper: Sendable {
    let service: String

    init(service: String = "com.pdfdiff.PdfDiff") {
        self.service = service
    }

    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first (update = delete + add)
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func read(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.readFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): "Keychain save failed (status \(s))"
        case .readFailed(let s): "Keychain read failed (status \(s))"
        case .deleteFailed(let s): "Keychain delete failed (status \(s))"
        }
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/KeychainHelper.swift PdfDiffApp/PdfDiffTests/Services/KeychainHelperTests.swift
git commit -m "feat: add KeychainHelper for secure API key storage"
```

---

### Task 3: SettingsManager

**Files:**
- Create: `PdfDiffApp/PdfDiff/ViewModels/SettingsManager.swift`
- Test: `PdfDiffApp/PdfDiffTests/ViewModels/SettingsManagerTests.swift`

**Step 1: Write tests**

Create `PdfDiffApp/PdfDiffTests/ViewModels/SettingsManagerTests.swift`:

```swift
import Testing
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
```

**Step 2: Run tests to verify they fail**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL — `SettingsManager` not found.

**Step 3: Implement SettingsManager**

Create `PdfDiffApp/PdfDiff/ViewModels/SettingsManager.swift`:

```swift
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
```

**Step 4: Run tests**

```bash
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/SettingsManager.swift PdfDiffApp/PdfDiffTests/ViewModels/SettingsManagerTests.swift
git commit -m "feat: add SettingsManager with Keychain-backed API key storage"
```

---

### Task 4: Settings View

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/SettingsView.swift`
- Modify: `PdfDiffApp/PdfDiff/PdfDiffApp.swift`

**Step 1: Create SettingsView**

Create `PdfDiffApp/PdfDiff/Views/SettingsView.swift`:

```swift
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
```

**Step 2: Wire Settings into PdfDiffApp.swift**

Modify `PdfDiffApp/PdfDiff/PdfDiffApp.swift`. Add a `@State private var settingsManager = SettingsManager()` property and a `Settings` scene:

Add after the existing `@State private var viewModel` line:
```swift
@State private var settingsManager = SettingsManager()
```

Add after the closing `}` of the `WindowGroup` scene (but before the final `}` of `body`):
```swift
Settings {
    SettingsView(settingsManager: settingsManager)
}
```

Also pass `settingsManager` into the environment by changing the `WindowGroup` content:
```swift
WindowGroup {
    AppView(viewModel: viewModel)
        .environment(settingsManager)
}
```

**Step 3: Regenerate Xcode project and build**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild build -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

**Step 4: Run all tests to confirm no regressions**

```bash
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/SettingsView.swift PdfDiffApp/PdfDiff/PdfDiffApp.swift
git commit -m "feat: add Settings view with OpenRouter API key configuration"
```

---

### Task 5: OpenRouterAIService Implementation

**Files:**
- Create: `PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift`
- Modify: `PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift`

**Step 1: Write tests for JSON parsing and image encoding**

Add to `AIAnalysisServiceTests.swift`:

```swift
@Test("AIAnalysisResult parses from valid OpenRouter JSON response")
func parsesValidResponse() throws {
    let json = """
    {
        "visual_changes": "The logo was moved 5mm left",
        "text_comparison": "Disclaimer paragraph was reworded",
        "qc_checklist": [
            {"check": "Bleed", "status": "pass", "detail": "3mm bleed present"},
            {"check": "Resolution", "status": "warn", "detail": "Logo is 150dpi, recommended 300dpi"}
        ],
        "anomalies": "No issues found"
    }
    """.data(using: .utf8)!

    let parsed = try OpenRouterAIService.parseAnalysisResponse(json)
    #expect(parsed.visualChanges == "The logo was moved 5mm left")
    #expect(parsed.textComparison == "Disclaimer paragraph was reworded")
    #expect(parsed.qcChecklist.count == 2)
    #expect(parsed.qcChecklist[0].status == .pass)
    #expect(parsed.qcChecklist[1].status == .warn)
    #expect(parsed.anomalies == "No issues found")
}

@Test("parseAnalysisResponse handles missing fields gracefully")
func parsesMissingFields() throws {
    let json = """
    {
        "visual_changes": "Something changed"
    }
    """.data(using: .utf8)!

    let parsed = try OpenRouterAIService.parseAnalysisResponse(json)
    #expect(parsed.visualChanges == "Something changed")
    #expect(parsed.textComparison.isEmpty)
    #expect(parsed.qcChecklist.isEmpty)
    #expect(parsed.anomalies.isEmpty)
}

@Test("encodeImageToBase64 produces valid base64 string")
func encodesImage() throws {
    let image = NSImage(size: NSSize(width: 100, height: 100))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: NSSize(width: 100, height: 100)).fill()
    image.unlockFocus()

    let base64 = try OpenRouterAIService.encodeImageToBase64(image, maxBytes: 1_000_000)
    #expect(!base64.isEmpty)
    // Verify it's valid base64 by decoding
    #expect(Data(base64Encoded: base64) != nil)
}
```

**Step 2: Run tests to verify they fail**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL — `OpenRouterAIService` not found.

**Step 3: Implement OpenRouterAIService**

Create `PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift`:

```swift
import Foundation
import AppKit

enum AIAnalysisError: Error, LocalizedError {
    case invalidAPIKey
    case rateLimited
    case networkError(String)
    case invalidResponse(String)
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: "Invalid API key — check Settings"
        case .rateLimited: "Rate limited — try again in a moment"
        case .networkError(let msg): "Network error: \(msg)"
        case .invalidResponse(let msg): "Invalid response: \(msg)"
        case .imageEncodingFailed: "Failed to encode image"
        }
    }
}

final class OpenRouterAIService: AIAnalysisServiceProtocol, @unchecked Sendable {
    private let apiKey: String
    private let model = "google/gemini-2.5-flash"
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func analyze(
        left: NSImage, right: NSImage, diff: NSImage,
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) async throws -> AIAnalysisResult {
        let leftB64 = try Self.encodeImageToBase64(left, maxBytes: 1_000_000)
        let rightB64 = try Self.encodeImageToBase64(right, maxBytes: 1_000_000)
        let diffB64 = try Self.encodeImageToBase64(diff, maxBytes: 1_000_000)

        let contextText = Self.buildContextText(
            leftText: leftText, rightText: rightText,
            diffResult: diffResult, structuralDiff: structuralDiff
        )

        let requestBody = Self.buildRequestBody(
            model: model,
            leftB64: leftB64, rightB64: rightB64, diffB64: diffB64,
            contextText: contextText
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PDF Diff Desktop", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIAnalysisError.networkError("No HTTP response")
        }

        switch http.statusCode {
        case 200: break
        case 401: throw AIAnalysisError.invalidAPIKey
        case 429: throw AIAnalysisError.rateLimited
        default: throw AIAnalysisError.networkError("HTTP \(http.statusCode)")
        }

        // Extract content from OpenRouter response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIAnalysisError.invalidResponse("Could not extract content from response")
        }

        // Try to parse as JSON, extracting from markdown code fence if needed
        let cleanedContent = Self.extractJSON(from: content)
        guard let contentData = cleanedContent.data(using: .utf8) else {
            throw AIAnalysisError.invalidResponse("Content not valid UTF-8")
        }

        do {
            return try Self.parseAnalysisResponse(contentData)
        } catch {
            // Fallback: treat the raw text as visual changes
            return AIAnalysisResult(
                visualChanges: content,
                textComparison: "",
                qcChecklist: [],
                anomalies: ""
            )
        }
    }

    // MARK: - Static Helpers (testable)

    static func encodeImageToBase64(_ image: NSImage, maxBytes: Int) throws -> String {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw AIAnalysisError.imageEncodingFailed
        }

        // Try quality 0.8 first, reduce to 0.6 if too large
        var quality: Double = 0.8
        var data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])

        if let d = data, d.count > maxBytes {
            quality = 0.6
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }

        guard let jpegData = data else {
            throw AIAnalysisError.imageEncodingFailed
        }

        return jpegData.base64EncodedString()
    }

    static func parseAnalysisResponse(_ data: Data) throws -> AIAnalysisResult {
        struct RawResponse: Decodable {
            let visual_changes: String?
            let text_comparison: String?
            let qc_checklist: [QCCheckItem]?
            let anomalies: String?
        }

        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        return AIAnalysisResult(
            visualChanges: raw.visual_changes ?? "",
            textComparison: raw.text_comparison ?? "",
            qcChecklist: raw.qc_checklist ?? [],
            anomalies: raw.anomalies ?? ""
        )
    }

    static func extractJSON(from content: String) -> String {
        // Strip markdown code fences if present
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let stripped = lines.dropFirst().dropLast().joined(separator: "\n")
            return stripped
        }
        return trimmed
    }

    static func buildContextText(
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) -> String {
        var parts: [String] = []

        parts.append("--- LEFT PAGE TEXT ---\n\(leftText.prefix(3000))")
        parts.append("--- RIGHT PAGE TEXT ---\n\(rightText.prefix(3000))")
        parts.append("--- DIFF SUMMARY ---")
        parts.append("Similarity: \(String(format: "%.2f%%", diffResult.similarityScore * 100))")
        parts.append("Changed pixels: \(diffResult.changedPixelCount) / \(diffResult.totalPixelCount)")
        parts.append("Changed regions: \(diffResult.changedRegions.count)")

        if !structuralDiff.metadataChanges.isEmpty {
            parts.append("Metadata changes: \(structuralDiff.metadataChanges.count)")
        }
        if !structuralDiff.textChanges.isEmpty {
            parts.append("Text changes on \(structuralDiff.textChanges.count) page(s)")
        }
        if !structuralDiff.pageSizeChanges.isEmpty {
            parts.append("Page size changes: \(structuralDiff.pageSizeChanges.count)")
        }

        return parts.joined(separator: "\n")
    }

    static func buildRequestBody(
        model: String,
        leftB64: String, rightB64: String, diffB64: String,
        contextText: String
    ) -> [String: Any] {
        let systemPrompt = """
        You are an expert prepress and print QC analyst. You analyze PDF page comparisons and provide structured feedback.

        You will receive three images:
        1. Left (original) page render
        2. Right (revised) page render
        3. Diff bitmap highlighting pixel-level changes in red

        You will also receive extracted text from both pages and a structured diff summary.

        Respond with valid JSON only (no markdown, no code fences) with exactly these keys:

        {
            "visual_changes": "Natural language description of all visual differences you can see between the two pages. Be specific about positions, sizes, colors.",
            "text_comparison": "Semantic summary of text content changes. Describe what was added, removed, or reworded and why it matters.",
            "qc_checklist": [
                {"check": "Check name", "status": "pass|warn|fail", "detail": "Explanation"}
            ],
            "anomalies": "Any unexpected, suspicious, or critical findings that warrant special attention."
        }

        For qc_checklist, evaluate these checks:
        - Bleed/trim safety: Are important elements too close to page edges?
        - Text readability: Is any text too small, overlapping, or poorly positioned?
        - Barcode/QR integrity: Are barcodes or QR codes intact and unchanged (if present)?
        - Color consistency: Are colors consistent between versions?
        - Image quality: Do images appear sharp and properly placed?
        - Font rendering: Do fonts appear consistent and properly rendered?
        - Alignment/registration: Are elements properly aligned between versions?
        - Unintended changes: Are there any changes that look accidental?

        If a section has nothing to report, say "No issues found" for that section.
        For qc_checklist, if a check is not applicable (e.g., no barcodes present), use status "pass" with detail "Not applicable".
        """

        return [
            "model": model,
            "temperature": 0,
            "max_tokens": 2000,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Analyze these two PDF pages and their differences:"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(leftB64)", "detail": "high"]],
                    ["type": "text", "text": "Left (original) page above. Right (revised) page below:"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(rightB64)", "detail": "high"]],
                    ["type": "text", "text": "Diff bitmap (changes highlighted in red):"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(diffB64)", "detail": "high"]],
                    ["type": "text", "text": contextText],
                ]],
            ],
        ]
    }
}
```

**Step 4: Run tests**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests PASS (including the 3 new parsing/encoding tests).

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift
git commit -m "feat: implement OpenRouterAIService with prompt engineering and response parsing"
```

---

### Task 6: CompareViewModel AI Integration

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift`
- Modify: `PdfDiffApp/PdfDiffTests/ViewModels/CompareViewModelTests.swift`

**Step 1: Write tests for AI integration**

Add to `CompareViewModelTests.swift`:

```swift
// MARK: - AI Analysis Tests

@Test("AI analysis defaults to nil")
func aiAnalysisDefaultsNil() async {
    let vm = CompareViewModel(pdfService: mockService)
    #expect(vm.aiResult == nil)
    #expect(!vm.isAnalyzing)
    #expect(vm.aiError == nil)
}

@Test("canRunAIAnalysis is false without documents")
func cannotRunWithoutDocs() async {
    let vm = CompareViewModel(pdfService: mockService)
    #expect(!vm.canRunAIAnalysis)
}

@Test("canRunAIAnalysis is false without API key")
func cannotRunWithoutKey() async {
    let left = try! mockService.openDocument(path: "/left.pdf")
    let right = try! mockService.openDocument(path: "/right.pdf")
    let vm = CompareViewModel(pdfService: mockService)
    await vm.setDocuments(left: left, right: right)
    // No AI service set
    #expect(!vm.canRunAIAnalysis)
}

@Test("runAIAnalysis populates result on success")
func aiAnalysisPopulatesResult() async {
    let left = try! mockService.openDocument(path: "/left.pdf")
    let right = try! mockService.openDocument(path: "/right.pdf")
    let vm = CompareViewModel(pdfService: mockService)
    let mockAI = MockAIAnalysisService()
    vm.aiService = mockAI
    await vm.setDocuments(left: left, right: right)

    await vm.runAIAnalysis()

    #expect(vm.aiResult != nil)
    #expect(vm.aiResult?.visualChanges == "Mock visual changes")
    #expect(vm.aiError == nil)
    #expect(mockAI.analyzeCallCount == 1)
}

@Test("runAIAnalysis sets error on failure")
func aiAnalysisSetsError() async {
    let left = try! mockService.openDocument(path: "/left.pdf")
    let right = try! mockService.openDocument(path: "/right.pdf")
    let vm = CompareViewModel(pdfService: mockService)
    let mockAI = MockAIAnalysisService()
    mockAI.mockError = AIAnalysisError.invalidAPIKey
    vm.aiService = mockAI
    await vm.setDocuments(left: left, right: right)

    await vm.runAIAnalysis()

    #expect(vm.aiResult == nil)
    #expect(vm.aiError != nil)
    #expect(vm.aiError!.contains("Invalid API key"))
}

@Test("AI results cleared on new comparison")
func aiResultsClearedOnNewComparison() async {
    let left = try! mockService.openDocument(path: "/left.pdf")
    let right = try! mockService.openDocument(path: "/right.pdf")
    let vm = CompareViewModel(pdfService: mockService)
    let mockAI = MockAIAnalysisService()
    vm.aiService = mockAI
    await vm.setDocuments(left: left, right: right)
    await vm.runAIAnalysis()
    #expect(vm.aiResult != nil)

    // Trigger new comparison
    await vm.renderAndDiff()
    #expect(vm.aiResult == nil)
}
```

**Step 2: Run tests to verify they fail**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: FAIL — `canRunAIAnalysis`, `aiService`, `runAIAnalysis` not found.

**Step 3: Add AI properties and methods to CompareViewModel**

Modify `PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift`.

Add these properties after the existing `var structuralDiff` line:

```swift
// AI Analysis
var aiResult: AIAnalysisResult?
var isAnalyzing = false
var aiError: String?
var aiService: AIAnalysisServiceProtocol?
private var aiTask: Task<Void, Never>?
```

Add a computed property:

```swift
var canRunAIAnalysis: Bool {
    hasDocuments && diffResult != nil && aiService != nil && !isAnalyzing
}
```

Add this method:

```swift
func runAIAnalysis() async {
    guard let left = leftImage, let right = rightImage,
          let diff = diffResult?.diffImage ?? leftImage,
          let service = aiService,
          let diffRes = diffResult,
          let structDiff = structuralDiff else { return }

    isAnalyzing = true
    aiError = nil

    // Extract text from documents (use empty string if unavailable)
    let leftText = (try? pdfService.extractPageText?(leftDocument!, currentPage)) ?? ""
    let rightText = (try? pdfService.extractPageText?(rightDocument!, currentPage)) ?? ""

    do {
        aiResult = try await service.analyze(
            left: left, right: right, diff: diff,
            leftText: leftText, rightText: rightText,
            diffResult: diffRes, structuralDiff: structDiff
        )
    } catch {
        aiError = error.localizedDescription
    }

    isAnalyzing = false
}
```

In the `renderAndDiff()` method, add `aiResult = nil` at the start (after the guard, before `zoomLevel = 1.0`) to clear stale AI results:

```swift
aiResult = nil
aiError = nil
```

**Note on text extraction:** The `PDFServiceProtocol` does not currently have an `extractPageText` method. For now, pass empty strings. The AI model still has the images and structured diff data which is sufficient. If text extraction is later added to the protocol, this can be updated. So change the `runAIAnalysis` to use empty strings directly:

```swift
func runAIAnalysis() async {
    guard let left = leftImage, let right = rightImage,
          let service = aiService,
          let diffRes = diffResult,
          let structDiff = structuralDiff else { return }

    let diffImage = diffRes.diffImage ?? left

    isAnalyzing = true
    aiError = nil

    do {
        aiResult = try await service.analyze(
            left: left, right: right, diff: diffImage,
            leftText: "", rightText: "",
            diffResult: diffRes, structuralDiff: structDiff
        )
    } catch {
        aiError = error.localizedDescription
    }

    isAnalyzing = false
}
```

**Step 4: Wire AI service in AppViewModel**

Modify `PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift`. The `CompareViewModel`'s `aiService` should be set when a `SettingsManager` is available. Add an `@Environment` or pass it through. The simplest approach: add a method to AppViewModel.

Add this method to `AppViewModel`:

```swift
func configureAIService(settingsManager: SettingsManager) {
    if settingsManager.hasAPIKey {
        compareViewModel.aiService = OpenRouterAIService(apiKey: settingsManager.apiKey)
    } else {
        compareViewModel.aiService = nil
    }
}
```

**Step 5: Run tests**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests PASS.

**Step 6: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift PdfDiffApp/PdfDiffTests/ViewModels/CompareViewModelTests.swift
git commit -m "feat: integrate AI analysis into CompareViewModel with cancellation support"
```

---

### Task 7: AI Results UI in DiffSummaryPanel

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/DiffSummaryPanel.swift`

**Step 1: Add AI result properties to DiffSummaryPanel**

Add these properties to the `DiffSummaryPanel` struct:

```swift
var aiResult: AIAnalysisResult?
var isAnalyzing: Bool = false
var aiError: String?
var onRetry: (() -> Void)?
```

Add state for disclosure groups:

```swift
@State private var isVisualExpanded = true
@State private var isTextCompExpanded = true
@State private var isQCExpanded = true
@State private var isAnomaliesExpanded = true
```

**Step 2: Add AI sections to the body**

Add after the structural diff sections (before the "No comparison data" check), inside the `VStack`:

```swift
// AI Analysis sections
if isAnalyzing {
    HStack {
        ProgressView()
            .controlSize(.small)
        Text("Analyzing with AI...")
            .foregroundStyle(.secondary)
    }
    .padding(.vertical, 8)
}

if let error = aiError {
    HStack {
        Image(systemName: "exclamation.triangle.fill")
            .foregroundStyle(.orange)
        Text(error)
            .foregroundStyle(.secondary)
        Spacer()
        if let retry = onRetry {
            Button("Retry") { retry() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
    .padding(.vertical, 4)
}

if let ai = aiResult {
    Divider().padding(.vertical, 4)

    aiVisualChangesSection(ai.visualChanges)
    aiTextComparisonSection(ai.textComparison)
    aiQCSection(ai.qcChecklist)
    aiAnomaliesSection(ai.anomalies)

    Button {
        copyAIReport(ai)
    } label: {
        Label("Copy AI Report", systemImage: "doc.on.doc")
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .padding(.top, 4)
}
```

**Step 3: Add the section view builders**

```swift
// MARK: - AI Analysis Sections

@ViewBuilder
private func aiVisualChangesSection(_ text: String) -> some View {
    DisclosureGroup(isExpanded: $isVisualExpanded) {
        Text(text)
            .font(.caption)
            .textSelection(.enabled)
            .padding(.top, 4)
    } label: {
        Label("Visual Changes", systemImage: "eye")
            .font(.headline)
    }
}

@ViewBuilder
private func aiTextComparisonSection(_ text: String) -> some View {
    DisclosureGroup(isExpanded: $isTextCompExpanded) {
        Text(text)
            .font(.caption)
            .textSelection(.enabled)
            .padding(.top, 4)
    } label: {
        Label("Text Comparison", systemImage: "text.magnifyingglass")
            .font(.headline)
    }
}

@ViewBuilder
private func aiQCSection(_ items: [QCCheckItem]) -> some View {
    DisclosureGroup(isExpanded: $isQCExpanded) {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: qcStatusIcon(item.status))
                        .foregroundStyle(qcStatusColor(item.status))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.check)
                            .font(.caption.bold())
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.top, 4)
    } label: {
        Label("Prepress QC", systemImage: "checklist")
            .font(.headline)
    }
}

@ViewBuilder
private func aiAnomaliesSection(_ text: String) -> some View {
    DisclosureGroup(isExpanded: $isAnomaliesExpanded) {
        HStack {
            if text != "No issues found" {
                Text(text)
                    .font(.caption)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    } label: {
        Label("Anomalies", systemImage: "exclamationmark.triangle")
            .font(.headline)
    }
}

private func qcStatusIcon(_ status: QCStatus) -> String {
    switch status {
    case .pass: "checkmark.circle.fill"
    case .warn: "exclamationmark.triangle.fill"
    case .fail: "xmark.circle.fill"
    }
}

private func qcStatusColor(_ status: QCStatus) -> Color {
    switch status {
    case .pass: .green
    case .warn: .yellow
    case .fail: .red
    }
}

private func copyAIReport(_ result: AIAnalysisResult) {
    var report = "## AI Analysis Report\n\n"
    report += "### Visual Changes\n\(result.visualChanges)\n\n"
    report += "### Text Comparison\n\(result.textComparison)\n\n"
    report += "### Prepress QC\n"
    for item in result.qcChecklist {
        let icon = item.status == .pass ? "✓" : item.status == .warn ? "⚠" : "✗"
        report += "\(icon) \(item.check): \(item.detail)\n"
    }
    report += "\n### Anomalies\n\(result.anomalies)\n"

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(report, forType: .string)
}
```

**Step 4: Update CompareView to pass AI data to DiffSummaryPanel**

Modify `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`. Update the `DiffSummaryPanel` call to pass the new properties:

```swift
DiffSummaryPanel(
    diffResult: viewModel.diffResult,
    structuralDiff: viewModel.structuralDiff,
    aiResult: viewModel.aiResult,
    isAnalyzing: viewModel.isAnalyzing,
    aiError: viewModel.aiError,
    onRetry: { Task { await viewModel.runAIAnalysis() } }
)
```

**Step 5: Regenerate, build, and test**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED, all tests PASS.

**Step 6: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/DiffSummaryPanel.swift PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift
git commit -m "feat: add AI analysis results UI with QC checklist and copy report"
```

---

### Task 8: Analyze Button in Compare Toolbar

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`
- Modify: `PdfDiffApp/PdfDiff/PdfDiffApp.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/AppView.swift`

**Step 1: Read AppView to understand environment wiring**

Read `PdfDiffApp/PdfDiff/Views/AppView.swift` to understand how the compare view is created.

**Step 2: Add "Analyze with AI" button to CompareView toolbar**

In `CompareView.swift`, add access to `SettingsManager` from the environment:

```swift
@Environment(SettingsManager.self) private var settingsManager: SettingsManager?
```

In the `compareToolbar` computed property, add the AI button between the zoom controls divider and the page navigation divider. Add after the zoom `HStack` closing brace and before the page nav `Divider`:

```swift
Divider().frame(height: 20)

Button {
    Task { await viewModel.runAIAnalysis() }
} label: {
    HStack(spacing: 4) {
        Image(systemName: "wand.and.stars")
        Text("Analyze")
    }
}
.disabled(!viewModel.canRunAIAnalysis)
.help(viewModel.aiService == nil ? "Set API key in Settings (⌘,)" : "Run AI analysis")
```

**Step 3: Wire SettingsManager to configure AI service**

In `PdfDiffApp.swift`, update `AppView` to observe `settingsManager` and configure the AI service. Add an `.onChange` modifier to the `WindowGroup`:

```swift
WindowGroup {
    AppView(viewModel: viewModel)
        .environment(settingsManager)
        .onChange(of: settingsManager.apiKey) {
            viewModel.configureAIService(settingsManager: settingsManager)
        }
        .onAppear {
            viewModel.configureAIService(settingsManager: settingsManager)
        }
}
```

**Note:** For `.onChange(of:)` to work, `SettingsManager.apiKey` must be observed. Since `SettingsManager` is `@Observable`, SwiftUI will track property accesses. However `.onChange(of:)` requires `Equatable`. Use a simpler approach — call `configureAIService` in `onAppear` and on settings window close. Or better: use `.task` with a watcher pattern. The simplest correct approach is to always create the service fresh when the analyze button is pressed.

**Alternative simpler approach:** Instead of watching for API key changes, have `CompareViewModel.runAIAnalysis` accept the API key directly:

In `CompareViewModel`, change `runAIAnalysis`:

```swift
func runAIAnalysis(apiKey: String) async {
    guard let left = leftImage, let right = rightImage,
          let diffRes = diffResult,
          let structDiff = structuralDiff else { return }

    let diffImage = diffRes.diffImage ?? left
    let service = OpenRouterAIService(apiKey: apiKey)

    isAnalyzing = true
    aiError = nil

    do {
        aiResult = try await service.analyze(
            left: left, right: right, diff: diffImage,
            leftText: "", rightText: "",
            diffResult: diffRes, structuralDiff: structDiff
        )
    } catch {
        aiError = error.localizedDescription
    }

    isAnalyzing = false
}
```

Update `canRunAIAnalysis` to not check `aiService`:

```swift
var canRunAIAnalysis: Bool {
    hasDocuments && diffResult != nil && !isAnalyzing
}
```

Remove the `aiService` property entirely — the service is created on-demand with the current API key.

Update the button:

```swift
Button {
    if let key = settingsManager?.apiKey, !key.isEmpty {
        Task { await viewModel.runAIAnalysis(apiKey: key) }
    }
} label: {
    HStack(spacing: 4) {
        Image(systemName: "wand.and.stars")
        Text("Analyze")
    }
}
.disabled(!viewModel.canRunAIAnalysis || settingsManager?.hasAPIKey != true)
.help(settingsManager?.hasAPIKey != true ? "Set API key in Settings (⌘,)" : "Run AI analysis")
```

Update `DiffSummaryPanel` retry closure:

```swift
onRetry: {
    if let key = settingsManager?.apiKey, !key.isEmpty {
        Task { await viewModel.runAIAnalysis(apiKey: key) }
    }
}
```

**Step 4: Update tests**

Update the AI tests in `CompareViewModelTests.swift` to use the new `runAIAnalysis(apiKey:)` signature. Replace `vm.aiService = mockAI` with passing a key. Since tests can't hit the real API, we need to keep the injectable service approach for tests.

Better approach: keep both. `runAIAnalysis` can accept an optional `AIAnalysisServiceProtocol` parameter, defaulting to creating a new `OpenRouterAIService`:

```swift
func runAIAnalysis(apiKey: String? = nil, service: AIAnalysisServiceProtocol? = nil) async {
    guard let left = leftImage, let right = rightImage,
          let diffRes = diffResult,
          let structDiff = structuralDiff else { return }

    let analysisService: AIAnalysisServiceProtocol
    if let service = service {
        analysisService = service
    } else if let key = apiKey, !key.isEmpty {
        analysisService = OpenRouterAIService(apiKey: key)
    } else {
        aiError = "No API key configured"
        return
    }

    let diffImage = diffRes.diffImage ?? left

    isAnalyzing = true
    aiError = nil

    do {
        aiResult = try await analysisService.analyze(
            left: left, right: right, diff: diffImage,
            leftText: "", rightText: "",
            diffResult: diffRes, structuralDiff: structDiff
        )
    } catch {
        aiError = error.localizedDescription
    }

    isAnalyzing = false
}
```

Tests use `service:` parameter, UI uses `apiKey:` parameter.

**Step 5: Regenerate, build, and test**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests PASS.

**Step 6: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift PdfDiffApp/PdfDiff/PdfDiffApp.swift PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift PdfDiffApp/PdfDiffTests/ViewModels/CompareViewModelTests.swift
git commit -m "feat: add Analyze with AI button in compare toolbar"
```

---

### Task 9: End-to-End Wiring and Polish

**Files:**
- Modify: `PdfDiffApp/PdfDiff/PdfDiffApp.swift` (if needed)
- Modify: `PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift` (clean up unused `configureAIService` if removed)

**Step 1: Clean up AppViewModel**

Remove `configureAIService` method from `AppViewModel` if it was added in Task 6 and is no longer needed (since we switched to on-demand service creation in Task 8).

**Step 2: Verify full build**

```bash
cd PdfDiffApp && xcodegen generate
xcodebuild build -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

**Step 3: Run all tests**

```bash
xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -30
```
Expected: All tests PASS (existing 16 + new AI tests).

**Step 4: Manual smoke test checklist**

1. Launch app, open Cmd+, — Settings window appears with AI section
2. API key field is a `SecureField`, "Verify" button is disabled until key is entered
3. Enter a key, click Verify — status should update (valid/invalid based on real key)
4. Open two PDFs, enter Compare mode
5. "Analyze" button is disabled if no API key is set
6. "Analyze" button is enabled when API key exists and diff is complete
7. Click "Analyze" — spinner appears, results populate in DiffSummaryPanel
8. "Copy AI Report" button copies formatted text to clipboard
9. Drop new documents — AI results clear
10. Network error shows inline error with Retry button

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: clean up AI analysis wiring and verify end-to-end"
```
