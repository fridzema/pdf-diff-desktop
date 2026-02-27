# Single-Document AI Inspection — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add AI-powered preflight QC and packaging regulatory inspection to the Inspector tab, with pin markers on the canvas and a clickable results sidebar.

**Architecture:** Extend `AIAnalysisServiceProtocol` with an `inspect()` method. New `InspectionResult` model with located issues. Inspector gets `ZoomableContainer` with pin overlay + right sidebar for results. Bidirectional selection between pins and sidebar.

**Tech Stack:** SwiftUI, Swift Testing, OpenRouter API (Gemini 2.5 Flash), existing `ZoomableContainer`

**Design doc:** `docs/plans/2026-02-27-ai-inspection-design.md`

---

### Task 1: Inspection Data Models

**Files:**
- Create: `PdfDiffApp/PdfDiff/Models/InspectionResult.swift`
- Test: `PdfDiffApp/PdfDiffTests/Models/InspectionResultTests.swift`

**Step 1: Write the failing tests**

```swift
// PdfDiffApp/PdfDiffTests/Models/InspectionResultTests.swift
import Testing
import Foundation
@testable import PdfDiff

@Suite("InspectionResult Tests")
struct InspectionResultTests {
    @Test("IssueSeverity raw values match expected JSON strings")
    func severityRawValues() {
        #expect(IssueSeverity.pass.rawValue == "pass")
        #expect(IssueSeverity.warn.rawValue == "warn")
        #expect(IssueSeverity.fail.rawValue == "fail")
    }

    @Test("IssueCategory raw values")
    func categoryRawValues() {
        #expect(IssueCategory.bleed.rawValue == "bleed")
        #expect(IssueCategory.barcodeUPC.rawValue == "barcodeUPC")
        #expect(IssueCategory.legalDisclaimers.rawValue == "legalDisclaimers")
    }

    @Test("IssueLocation stores percentage-based coordinates")
    func locationCoordinates() {
        let loc = IssueLocation(x: 0.1, y: 0.2, w: 0.5, h: 0.3)
        #expect(loc.x == 0.1)
        #expect(loc.y == 0.2)
        #expect(loc.w == 0.5)
        #expect(loc.h == 0.3)
    }

    @Test("IssueLocation centerX and centerY computed correctly")
    func locationCenter() {
        let loc = IssueLocation(x: 0.1, y: 0.2, w: 0.5, h: 0.3)
        #expect(loc.centerX == 0.35)  // 0.1 + 0.5/2
        #expect(loc.centerY == 0.35)  // 0.2 + 0.3/2
    }

    @Test("InspectionIssue has correct identity")
    func issueIdentity() {
        let issue = InspectionIssue(
            id: 1, severity: .fail, category: .bleed,
            title: "No bleed", detail: "Artwork has no bleed area",
            location: IssueLocation(x: 0, y: 0, w: 1, h: 0.05)
        )
        #expect(issue.id == 1)
        #expect(issue.severity == .fail)
        #expect(issue.category == .bleed)
        #expect(issue.location != nil)
    }

    @Test("InspectionIssue works without location")
    func issueWithoutLocation() {
        let issue = InspectionIssue(
            id: 2, severity: .warn, category: .colorSpace,
            title: "RGB color space", detail: "Document uses RGB",
            location: nil
        )
        #expect(issue.location == nil)
    }

    @Test("InspectionResult holds issues and summary")
    func resultStructure() {
        let result = InspectionResult(
            issues: [
                InspectionIssue(id: 1, severity: .pass, category: .bleed,
                    title: "OK", detail: "3mm bleed", location: nil)
            ],
            summary: "1 issue found"
        )
        #expect(result.issues.count == 1)
        #expect(result.summary == "1 issue found")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: Compilation errors — types not defined yet.

**Step 3: Write the implementation**

```swift
// PdfDiffApp/PdfDiff/Models/InspectionResult.swift
import Foundation

struct InspectionResult {
    let issues: [InspectionIssue]
    let summary: String
}

struct InspectionIssue: Identifiable {
    let id: Int
    let severity: IssueSeverity
    let category: IssueCategory
    let title: String
    let detail: String
    let location: IssueLocation?
}

struct IssueLocation {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var centerX: Double { x + w / 2 }
    var centerY: Double { y + h / 2 }
}

enum IssueSeverity: String, Codable {
    case pass, warn, fail
}

enum IssueCategory: String, Codable {
    case bleed, resolution, colorSpace, fontEmbedding
    case overprint, transparency, barcodeUPC
    case requiredText, nutritionPanel, allergenWarning
    case recyclingSymbols, countryOfOrigin, legalDisclaimers
}
```

**Step 4: Run tests to verify they pass**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All InspectionResult tests pass.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Models/InspectionResult.swift PdfDiffApp/PdfDiffTests/Models/InspectionResultTests.swift PdfDiffApp/project.yml
git commit -m "feat: add InspectionResult data models for single-document AI inspection"
```

---

### Task 2: Inspection Response Parsing

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift` (add `parseInspectionResponse` static method)
- Test: `PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift` (add inspection parsing tests)

**Step 1: Write the failing tests**

Add to `AIAnalysisServiceTests.swift`:

```swift
@Test("parseInspectionResponse parses valid JSON with locations")
func parsesInspectionWithLocations() throws {
    let json = """
    {
        "issues": [
            {
                "id": 1, "severity": "fail", "category": "bleed",
                "title": "No bleed detected",
                "detail": "Artwork ends at trim edge",
                "location": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 0.05}
            },
            {
                "id": 2, "severity": "warn", "category": "resolution",
                "title": "Low-res image",
                "detail": "Hero image is 150dpi",
                "location": {"x": 0.2, "y": 0.3, "w": 0.4, "h": 0.3}
            }
        ],
        "summary": "2 issues found: 1 critical, 1 warning"
    }
    """.data(using: .utf8)!

    let result = try OpenRouterAIService.parseInspectionResponse(json)
    #expect(result.issues.count == 2)
    #expect(result.issues[0].severity == .fail)
    #expect(result.issues[0].category == .bleed)
    #expect(result.issues[0].location?.x == 0.0)
    #expect(result.issues[0].location?.h == 0.05)
    #expect(result.issues[1].location?.centerX == 0.4)
    #expect(result.summary.contains("2 issues"))
}

@Test("parseInspectionResponse handles null location")
func parsesInspectionNullLocation() throws {
    let json = """
    {
        "issues": [
            {
                "id": 1, "severity": "warn", "category": "colorSpace",
                "title": "RGB color space",
                "detail": "Document uses RGB instead of CMYK",
                "location": null
            }
        ],
        "summary": "1 issue"
    }
    """.data(using: .utf8)!

    let result = try OpenRouterAIService.parseInspectionResponse(json)
    #expect(result.issues.count == 1)
    #expect(result.issues[0].location == nil)
}

@Test("parseInspectionResponse handles empty issues array")
func parsesEmptyIssues() throws {
    let json = """
    {"issues": [], "summary": "No issues found"}
    """.data(using: .utf8)!

    let result = try OpenRouterAIService.parseInspectionResponse(json)
    #expect(result.issues.isEmpty)
    #expect(result.summary == "No issues found")
}

@Test("parseInspectionResponse handles unknown category gracefully")
func parsesUnknownCategory() throws {
    let json = """
    {
        "issues": [
            {
                "id": 1, "severity": "warn", "category": "unknownNewCheck",
                "title": "Some check",
                "detail": "Detail",
                "location": null
            }
        ],
        "summary": "1 issue"
    }
    """.data(using: .utf8)!

    // Unknown category should not crash — the issue should still be parsed
    // with a fallback category or the parser should handle it
    let result = try OpenRouterAIService.parseInspectionResponse(json)
    #expect(result.issues.count == 1)
}
```

**Step 2: Run tests to verify they fail**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: `parseInspectionResponse` method not found.

**Step 3: Write the implementation**

Add to `OpenRouterAIService.swift` in the `// MARK: - Static Helpers` section:

```swift
static func parseInspectionResponse(_ data: Data) throws -> InspectionResult {
    struct RawLocation: Decodable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    struct RawIssue: Decodable {
        let id: Int
        let severity: String
        let category: String
        let title: String
        let detail: String
        let location: RawLocation?
    }

    struct RawInspectionResponse: Decodable {
        let issues: [RawIssue]
        let summary: String
    }

    let raw = try JSONDecoder().decode(RawInspectionResponse.self, from: data)

    let issues = raw.issues.map { rawIssue in
        InspectionIssue(
            id: rawIssue.id,
            severity: IssueSeverity(rawValue: rawIssue.severity) ?? .warn,
            category: IssueCategory(rawValue: rawIssue.category) ?? .requiredText,
            title: rawIssue.title,
            detail: rawIssue.detail,
            location: rawIssue.location.map {
                IssueLocation(x: $0.x, y: $0.y, w: $0.w, h: $0.h)
            }
        )
    }

    return InspectionResult(issues: issues, summary: raw.summary)
}
```

**Step 4: Run tests to verify they pass**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All new parsing tests pass.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift
git commit -m "feat: add inspection response JSON parser with location support"
```

---

### Task 3: Extend AI Service Protocol with `inspect()` Method

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Services/AIAnalysisService.swift` (add `inspect()` to protocol + mock)
- Modify: `PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift` (implement `inspect()`)
- Test: `PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift` (add mock inspect tests)

**Step 1: Write the failing tests**

Add to `AIAnalysisServiceTests.swift`:

```swift
@Test("MockAIAnalysisService inspect returns default result")
@MainActor
func mockInspectReturnsDefault() async throws {
    let mock = MockAIAnalysisService()
    let dummyImage = NSImage(size: NSSize(width: 100, height: 100))
    let metadata = PDFMetadata(
        title: "Test", author: nil, creator: nil, producer: nil,
        creationDate: nil, modificationDate: nil, pdfVersion: "1.7",
        pageCount: 1, fileSizeBytes: 1000, isEncrypted: false, colorProfiles: ["sRGB"]
    )
    let pageMetadata = PDFPageMetadata(
        pageNumber: 0, widthPt: 612, heightPt: 792,
        rotation: 0, fontNames: ["Helvetica"], imageCount: 2
    )

    let result = try await mock.inspect(
        image: dummyImage, metadata: metadata, pageMetadata: pageMetadata
    )
    #expect(!result.issues.isEmpty)
    #expect(!result.summary.isEmpty)
    #expect(mock.inspectCallCount == 1)
}

@Test("MockAIAnalysisService inspect throws when configured")
@MainActor
func mockInspectThrows() async {
    let mock = MockAIAnalysisService()
    mock.mockError = AIAnalysisError.invalidAPIKey
    let dummyImage = NSImage(size: NSSize(width: 10, height: 10))
    let metadata = PDFMetadata(
        title: nil, author: nil, creator: nil, producer: nil,
        creationDate: nil, modificationDate: nil, pdfVersion: "1.4",
        pageCount: 1, fileSizeBytes: 500, isEncrypted: false, colorProfiles: []
    )
    let pageMetadata = PDFPageMetadata(
        pageNumber: 0, widthPt: 612, heightPt: 792,
        rotation: 0, fontNames: [], imageCount: 0
    )

    do {
        _ = try await mock.inspect(
            image: dummyImage, metadata: metadata, pageMetadata: pageMetadata
        )
        Issue.record("Expected error")
    } catch {
        #expect(error is AIAnalysisError)
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: `inspect` method not found on protocol/mock.

**Step 3: Write the implementation**

**3a. Update protocol** in `AIAnalysisService.swift`:

Add `inspect` method to `AIAnalysisServiceProtocol`:

```swift
protocol AIAnalysisServiceProtocol: Sendable {
    func analyze(
        left: NSImage, right: NSImage, diff: NSImage,
        leftText: String, rightText: String,
        diffResult: PDFDiffResult,
        structuralDiff: PDFStructuralDiffResult
    ) async throws -> AIAnalysisResult

    func inspect(
        image: NSImage, metadata: PDFMetadata, pageMetadata: PDFPageMetadata
    ) async throws -> InspectionResult
}
```

**3b. Update MockAIAnalysisService** in `AIAnalysisService.swift`:

Add to the mock class:

```swift
var mockInspectionResult: InspectionResult?
var inspectCallCount = 0

func inspect(
    image: NSImage, metadata: PDFMetadata, pageMetadata: PDFPageMetadata
) async throws -> InspectionResult {
    inspectCallCount += 1
    if let error = mockError { throw error }
    return mockInspectionResult ?? InspectionResult(
        issues: [
            InspectionIssue(id: 1, severity: .pass, category: .bleed,
                title: "Bleed OK", detail: "3mm bleed present", location: nil)
        ],
        summary: "Mock inspection: 1 check passed"
    )
}
```

**3c. Implement `inspect()` on OpenRouterAIService** in `OpenRouterAIService.swift`:

```swift
func inspect(
    image: NSImage, metadata: PDFMetadata, pageMetadata: PDFPageMetadata
) async throws -> InspectionResult {
    let imageB64 = try Self.encodeImageToBase64(image, maxBytes: 1_000_000)
    let contextText = Self.buildInspectionContext(metadata: metadata, pageMetadata: pageMetadata)
    let requestBody = Self.buildInspectionRequestBody(model: model, imageB64: imageB64, contextText: contextText)

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

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let content = message["content"] as? String else {
        throw AIAnalysisError.invalidResponse("Could not extract content from response")
    }

    let cleanedContent = Self.extractJSON(from: content)
    guard let contentData = cleanedContent.data(using: .utf8) else {
        throw AIAnalysisError.invalidResponse("Content not valid UTF-8")
    }

    return try Self.parseInspectionResponse(contentData)
}
```

Also add two new static helpers:

```swift
static func buildInspectionContext(metadata: PDFMetadata, pageMetadata: PDFPageMetadata) -> String {
    var parts: [String] = []
    parts.append("--- DOCUMENT METADATA ---")
    parts.append("PDF Version: \(metadata.pdfVersion)")
    parts.append("Pages: \(metadata.pageCount)")
    parts.append("File size: \(metadata.fileSizeBytes) bytes")
    parts.append("Encrypted: \(metadata.isEncrypted)")
    if !metadata.colorProfiles.isEmpty {
        parts.append("Color profiles: \(metadata.colorProfiles.joined(separator: ", "))")
    }
    parts.append("--- PAGE 1 ---")
    parts.append("Size: \(pageMetadata.widthPt)pt x \(pageMetadata.heightPt)pt")
    parts.append("Rotation: \(pageMetadata.rotation)°")
    if !pageMetadata.fontNames.isEmpty {
        parts.append("Fonts: \(pageMetadata.fontNames.joined(separator: ", "))")
    }
    parts.append("Images: \(pageMetadata.imageCount)")
    return parts.joined(separator: "\n")
}

static func buildInspectionRequestBody(model: String, imageB64: String, contextText: String) -> [String: Any] {
    let systemPrompt = """
    You are an expert prepress QC inspector and packaging compliance analyst. You inspect a single PDF artwork page for print-readiness and regulatory compliance issues.

    You will receive one image: a rendered PDF page. You will also receive document metadata (fonts, color profiles, page dimensions).

    Respond with valid JSON only (no markdown, no code fences) with exactly these keys:

    {
        "issues": [
            {
                "id": 1,
                "severity": "pass|warn|fail",
                "category": "category_name",
                "title": "Short title",
                "detail": "Full explanation of the issue",
                "location": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 0.1} or null
            }
        ],
        "summary": "One-paragraph overall assessment"
    }

    Location coordinates are percentages (0.0 to 1.0) relative to the page:
    - x: distance from left edge
    - y: distance from top edge
    - w: width as fraction of page width
    - h: height as fraction of page height
    Set location to null for page-wide issues (e.g., wrong color space).

    Valid categories: bleed, resolution, colorSpace, fontEmbedding, overprint, transparency, barcodeUPC, requiredText, nutritionPanel, allergenWarning, recyclingSymbols, countryOfOrigin, legalDisclaimers

    Evaluate ALL of these checks:

    PREPRESS QC:
    - Bleed/trim safety: Does artwork extend beyond the visible content area? Are critical elements too close to edges?
    - Image resolution: Do images appear sharp at print size, or pixelated/low-res?
    - Color space: Based on color profiles metadata, is the document CMYK-ready or still RGB?
    - Font embedding: Are fonts listed in metadata standard print fonts? Any potential embedding issues?
    - Overprint/knockout: Any visible overprint artifacts or misregistration signs?
    - Transparency: Any visible transparency flattening issues?

    PACKAGING REGULATORY:
    - Required text: Are mandatory text elements present and legible (ingredient lists, warnings, etc.)?
    - Barcode/UPC: Is a barcode present? Does it appear intact and scannable?
    - Nutrition panel: If a nutrition facts panel is present, is it properly formatted?
    - Allergen warnings: Are allergen declarations visible and prominent?
    - Recycling symbols: Are recycling/disposal symbols present?
    - Country of origin: Is country of origin text present?
    - Legal disclaimers: Are trademark symbols (R), (TM) and required legal text present?

    For each check, report severity:
    - "pass": Check passes, no issues
    - "warn": Minor concern or could not fully verify
    - "fail": Clear issue that needs attention

    Include all checks in the issues array, even passing ones. Be specific about what you see.
    """

    return [
        "model": model,
        "temperature": 0,
        "max_tokens": 3000,
        "messages": [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": [
                ["type": "text", "text": "Inspect this PDF artwork page for prepress and packaging compliance issues:"],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageB64)", "detail": "high"]],
                ["type": "text", "text": contextText],
            ]],
        ],
    ]
}
```

**Step 4: Run tests to verify they pass**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass including the new mock inspect tests.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Services/AIAnalysisService.swift PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift PdfDiffApp/PdfDiffTests/Services/AIAnalysisServiceTests.swift
git commit -m "feat: extend AI service protocol with inspect() for single-document analysis"
```

---

### Task 4: InspectorViewModel Inspection State & Logic

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Create: `PdfDiffApp/PdfDiffTests/ViewModels/InspectorViewModelTests.swift`

**Step 1: Write the failing tests**

```swift
// PdfDiffApp/PdfDiffTests/ViewModels/InspectorViewModelTests.swift
import Testing
import AppKit
@testable import PdfDiff

@Suite("InspectorViewModel Tests")
@MainActor
struct InspectorViewModelTests {
    let mockService = MockPDFService()

    @Test("inspection state defaults to nil/false")
    func inspectionDefaults() {
        let vm = InspectorViewModel(pdfService: mockService)
        #expect(vm.inspectionResult == nil)
        #expect(!vm.isInspecting)
        #expect(vm.inspectionError == nil)
        #expect(vm.selectedIssueId == nil)
        #expect(!vm.showInspectionSidebar)
        #expect(vm.showPins)
    }

    @Test("canRunInspection is false without document")
    func cannotInspectWithoutDoc() {
        let vm = InspectorViewModel(pdfService: mockService)
        #expect(!vm.canRunInspection)
    }

    @Test("canRunInspection is true with document and rendered image")
    func canInspectWithDoc() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)
        #expect(vm.canRunInspection)
    }

    @Test("runInspection populates result on success")
    func inspectionSuccess() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)

        let mockAI = MockAIAnalysisService()
        await vm.runInspection(service: mockAI)

        #expect(vm.inspectionResult != nil)
        #expect(vm.inspectionError == nil)
        #expect(vm.showInspectionSidebar)
        #expect(!vm.isInspecting)
        #expect(mockAI.inspectCallCount == 1)
    }

    @Test("runInspection sets error on failure")
    func inspectionFailure() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)

        let mockAI = MockAIAnalysisService()
        mockAI.mockError = AIAnalysisError.invalidAPIKey
        await vm.runInspection(service: mockAI)

        #expect(vm.inspectionResult == nil)
        #expect(vm.inspectionError != nil)
        #expect(vm.inspectionError!.contains("Invalid API key"))
        #expect(!vm.isInspecting)
    }

    @Test("runInspection without key or service sets error")
    func inspectionNoKey() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc = try! mockService.openDocument(path: "/test.pdf")
        await vm.loadDocument(doc)

        await vm.runInspection()

        #expect(vm.inspectionError == "No API key configured")
    }

    @Test("inspection results cleared on new document")
    func resultsClearedOnNewDoc() async {
        let vm = InspectorViewModel(pdfService: mockService)
        let doc1 = try! mockService.openDocument(path: "/test1.pdf")
        await vm.loadDocument(doc1)
        let mockAI = MockAIAnalysisService()
        await vm.runInspection(service: mockAI)
        #expect(vm.inspectionResult != nil)

        let doc2 = try! mockService.openDocument(path: "/test2.pdf")
        await vm.loadDocument(doc2)
        #expect(vm.inspectionResult == nil)
        #expect(!vm.showInspectionSidebar)
    }

    @Test("selectedIssueId can be set and cleared")
    func selectedIssueId() async {
        let vm = InspectorViewModel(pdfService: mockService)
        vm.selectedIssueId = 1
        #expect(vm.selectedIssueId == 1)
        vm.selectedIssueId = nil
        #expect(vm.selectedIssueId == nil)
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: New properties/methods not found on `InspectorViewModel`.

**Step 3: Write the implementation**

Modify `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`:

```swift
import Foundation
import AppKit

@Observable @MainActor
final class InspectorViewModel {
    var document: OpenedDocument?
    var currentPage: UInt32 = 0
    var renderedImage: NSImage?
    var metadata: PDFMetadata?
    var pagesMetadata: [PDFPageMetadata] = []
    var isRendering = false
    var errorMessage: String?

    // Inspection state
    var inspectionResult: InspectionResult?
    var isInspecting = false
    var inspectionError: String?
    var selectedIssueId: Int?
    var showInspectionSidebar = false
    var showPins = true

    private let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    var canRunInspection: Bool {
        document != nil && renderedImage != nil && !isInspecting
    }

    func loadDocument(_ doc: OpenedDocument) async {
        self.document = doc
        self.currentPage = 0
        self.inspectionResult = nil
        self.inspectionError = nil
        self.selectedIssueId = nil
        self.showInspectionSidebar = false

        do {
            self.metadata = try pdfService.metadata(document: doc)
            self.pagesMetadata = try pdfService.pagesMetadata(document: doc)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        await renderCurrentPage()
    }

    func runInspection(apiKey: String? = nil, service: AIAnalysisServiceProtocol? = nil) async {
        guard let image = renderedImage,
              let meta = metadata,
              !pagesMetadata.isEmpty else { return }

        let analysisService: AIAnalysisServiceProtocol
        if let service = service {
            analysisService = service
        } else if let key = apiKey, !key.isEmpty {
            analysisService = OpenRouterAIService(apiKey: key)
        } else {
            inspectionError = "No API key configured"
            return
        }

        isInspecting = true
        inspectionError = nil
        inspectionResult = nil
        selectedIssueId = nil

        do {
            inspectionResult = try await analysisService.inspect(
                image: image, metadata: meta, pageMetadata: pagesMetadata[0]
            )
            showInspectionSidebar = true
        } catch {
            inspectionError = error.localizedDescription
        }

        isInspecting = false
    }

    func nextPage() {
        guard let doc = document, currentPage < doc.pageCount - 1 else { return }
        currentPage += 1
        Task { await renderCurrentPage() }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        Task { await renderCurrentPage() }
    }

    private func renderCurrentPage() async {
        guard let doc = document else { return }
        isRendering = true
        defer { isRendering = false }

        do {
            let rendered = try pdfService.renderPage(document: doc, page: currentPage, dpi: 150)
            self.renderedImage = rendered.image
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All InspectorViewModel tests pass.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift PdfDiffApp/PdfDiffTests/ViewModels/InspectorViewModelTests.swift
git commit -m "feat: add inspection state and runInspection to InspectorViewModel"
```

---

### Task 5: IssuePinView Component

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift`

This is a pure UI component — no unit tests needed, verify visually.

**Step 1: Write the implementation**

```swift
// PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift
import SwiftUI

struct IssuePinView: View {
    let issue: InspectionIssue
    let isSelected: Bool
    var onTap: () -> Void = {}

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring (selected only)
            if isSelected {
                Circle()
                    .stroke(severityColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
            }

            // Pin circle
            Circle()
                .fill(severityColor)
                .frame(width: isSelected ? 28 : 24, height: isSelected ? 28 : 24)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            // Number
            Text("\(issue.id)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .onTapGesture { onTap() }
        .onAppear {
            if isSelected { isPulsing = true }
        }
        .onChange(of: isSelected) { _, selected in
            isPulsing = selected
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .fail: .red
        case .warn: .orange
        case .pass: .green
        }
    }
}
```

**Step 2: Regenerate Xcode project and verify it compiles**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild build -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift
git commit -m "feat: add IssuePinView numbered pin marker component"
```

---

### Task 6: InspectionSidebar Component

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Inspector/InspectionSidebar.swift`

**Step 1: Write the implementation**

```swift
// PdfDiffApp/PdfDiff/Views/Inspector/InspectionSidebar.swift
import SwiftUI

struct InspectionSidebar: View {
    let result: InspectionResult
    @Binding var selectedIssueId: Int?
    @Binding var showPins: Bool
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            issueList
            Divider()
            footer
        }
        .frame(width: 280)
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Inspection Results")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(result.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                severityBadge(.fail, count: result.issues.filter { $0.severity == .fail }.count)
                severityBadge(.warn, count: result.issues.filter { $0.severity == .warn }.count)
                severityBadge(.pass, count: result.issues.filter { $0.severity == .pass }.count)
            }
        }
        .padding(12)
    }

    private func severityBadge(_ severity: IssueSeverity, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: severityIcon(severity))
                .font(.caption2)
                .foregroundStyle(severityColor(severity))
            Text("\(count)")
                .font(.caption.monospacedDigit())
        }
    }

    // MARK: - Issue List

    private var issueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.issues) { issue in
                        issueRow(issue)
                            .id(issue.id)
                        Divider()
                    }
                }
            }
            .onChange(of: selectedIssueId) { _, newId in
                if let id = newId {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func issueRow(_ issue: InspectionIssue) -> some View {
        let isSelected = selectedIssueId == issue.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: severityIcon(issue.severity))
                    .foregroundStyle(severityColor(issue.severity))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("#\(issue.id)")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                        Text(issue.title)
                            .font(.caption.bold())
                            .lineLimit(isSelected ? nil : 1)
                    }

                    Text(issue.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())

                    if isSelected {
                        Text(issue.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedIssueId = isSelected ? nil : issue.id
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                copyReport()
            } label: {
                Label("Copy Report", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Toggle(isOn: $showPins) {
                Label("Pins", systemImage: "mappin")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func severityIcon(_ severity: IssueSeverity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    private func severityColor(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .pass: .green
        case .warn: .orange
        case .fail: .red
        }
    }

    private func copyReport() {
        var report = "## AI Inspection Report\n\n"
        report += "**Summary:** \(result.summary)\n\n"
        for issue in result.issues {
            let icon = issue.severity == .pass ? "✓" : issue.severity == .warn ? "⚠" : "✗"
            report += "\(icon) **#\(issue.id) \(issue.title)** [\(issue.severity.rawValue.uppercased())]\n"
            report += "  Category: \(issue.category.rawValue)\n"
            report += "  \(issue.detail)\n\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
```

**Step 2: Regenerate Xcode project and verify it compiles**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild build -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/InspectionSidebar.swift
git commit -m "feat: add InspectionSidebar with issue list and copy report"
```

---

### Task 7: Upgrade InspectorView with ZoomableContainer, Pins, and Sidebar

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`

**Step 1: Write the implementation**

Replace the entire `InspectorView`:

```swift
import SwiftUI

struct InspectorView: View {
    @State var viewModel: InspectorViewModel
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager?

    var body: some View {
        VSplitView {
            // Top area: page renderer + optional sidebar
            VStack(spacing: 0) {
                toolbar
                Divider()

                HStack(spacing: 0) {
                    // Canvas with pins
                    pageCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Inspection sidebar (slides in from right)
                    if viewModel.showInspectionSidebar, let result = viewModel.inspectionResult {
                        Divider()
                        InspectionSidebar(
                            result: result,
                            selectedIssueId: $viewModel.selectedIssueId,
                            showPins: $viewModel.showPins,
                            onClose: { viewModel.showInspectionSidebar = false }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
            }
            .frame(minHeight: 300)
            .animation(.easeInOut(duration: 0.25), value: viewModel.showInspectionSidebar)

            // Metadata panel
            MetadataPanel(metadata: viewModel.metadata, pageMetadata: viewModel.pagesMetadata)
                .frame(minHeight: 150, maxHeight: 300)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button(action: { viewModel.previousPage() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.currentPage == 0)

            Text("Page \(viewModel.currentPage + 1) of \(viewModel.document?.pageCount ?? 0)")
                .font(.body.monospacedDigit())

            Button(action: { viewModel.nextPage() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.currentPage >= (viewModel.document?.pageCount ?? 1) - 1)

            Spacer()

            if viewModel.isInspecting {
                ProgressView()
                    .controlSize(.small)
                Text("Inspecting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.inspectionError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Retry") {
                    if let key = settingsManager?.apiKey, !key.isEmpty {
                        Task { await viewModel.runInspection(apiKey: key) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if viewModel.inspectionResult != nil && !viewModel.showInspectionSidebar {
                Button {
                    viewModel.showInspectionSidebar = true
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help("Show inspection results")
            }

            Button {
                if let key = settingsManager?.apiKey, !key.isEmpty {
                    Task { await viewModel.runInspection(apiKey: key) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("Inspect")
                }
            }
            .disabled(!viewModel.canRunInspection || settingsManager?.hasAPIKey != true)
            .help(settingsManager?.hasAPIKey != true ? "Set API key in Settings (\u{2318},)" : "Run AI inspection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Page Canvas

    @ViewBuilder
    private var pageCanvas: some View {
        if viewModel.isRendering {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = viewModel.renderedImage {
            ZoomableContainer {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    // Pin overlay
                    if viewModel.showPins && viewModel.currentPage == 0,
                       let result = viewModel.inspectionResult {
                        GeometryReader { geo in
                            ForEach(result.issues.filter { $0.location != nil }) { issue in
                                let loc = issue.location!
                                IssuePinView(
                                    issue: issue,
                                    isSelected: viewModel.selectedIssueId == issue.id
                                ) {
                                    viewModel.selectedIssueId = viewModel.selectedIssueId == issue.id ? nil : issue.id
                                }
                                .position(
                                    x: loc.centerX * geo.size.width,
                                    y: loc.centerY * geo.size.height
                                )
                            }
                        }
                    }
                }
            }
        } else {
            Text("No page rendered")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

**Step 2: Regenerate Xcode project and verify it compiles**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild build -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

**Step 3: Run all tests to verify nothing broke**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift
git commit -m "feat: upgrade InspectorView with ZoomableContainer, pin overlay, and inspection sidebar"
```

---

### Task 8: Issue Pin Popover

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift`

The pin currently just shows a number. Add a popover that appears on tap showing the full issue detail.

**Step 1: Write the implementation**

Update `IssuePinView` to include a popover:

Replace the `onTapGesture` and add a `@State private var showPopover = false`:

```swift
struct IssuePinView: View {
    let issue: InspectionIssue
    let isSelected: Bool
    var onTap: () -> Void = {}

    @State private var isPulsing = false
    @State private var showPopover = false

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .stroke(severityColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
            }

            Circle()
                .fill(severityColor)
                .frame(width: isSelected ? 28 : 24, height: isSelected ? 28 : 24)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            Text("\(issue.id)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .onTapGesture {
            onTap()
            showPopover = true
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: severityIcon)
                        .foregroundStyle(severityColor)
                    Text(issue.title)
                        .font(.headline)
                }
                Text(issue.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 260)
        }
        .onAppear {
            if isSelected { isPulsing = true }
        }
        .onChange(of: isSelected) { _, selected in
            isPulsing = selected
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .fail: .red
        case .warn: .orange
        case .pass: .green
        }
    }

    private var severityIcon: String {
        switch issue.severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `cd PdfDiffApp && xcodebuild build -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift
git commit -m "feat: add popover with issue detail to IssuePinView"
```

---

### Task 9: Final Integration — Verify All Tests & Build

**Files:** None new — verification only.

**Step 1: Regenerate Xcode project**

Run: `cd PdfDiffApp && xcodegen generate`

**Step 2: Run full test suite**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiffTests -destination 'platform=macOS' 2>&1 | tail -40`
Expected: All tests pass (existing 39 + new InspectionResult tests + new parsing tests + new InspectorViewModel tests).

**Step 3: Build the app**

Run: `cd PdfDiffApp && xcodebuild build -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

**Step 4: Verify file structure**

New files created:
- `PdfDiffApp/PdfDiff/Models/InspectionResult.swift`
- `PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift`
- `PdfDiffApp/PdfDiff/Views/Inspector/InspectionSidebar.swift`
- `PdfDiffApp/PdfDiffTests/Models/InspectionResultTests.swift`
- `PdfDiffApp/PdfDiffTests/ViewModels/InspectorViewModelTests.swift`

Modified files:
- `PdfDiffApp/PdfDiff/Services/AIAnalysisService.swift` (protocol + mock)
- `PdfDiffApp/PdfDiff/Services/OpenRouterAIService.swift` (inspect + parsing + prompt)
- `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift` (inspection state)
- `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift` (ZoomableContainer + pins + sidebar)
