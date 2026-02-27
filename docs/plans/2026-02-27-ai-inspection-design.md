# Single-Document AI Inspection — Design

## Purpose

Add AI-powered preflight QC and packaging regulatory inspection to the Inspector tab's single-document view. The AI analyzes page 1 of a PDF artwork, identifies issues (bleed violations, low-res images, missing regulatory text, etc.), returns approximate locations, and the UI shows numbered pin markers on the canvas with a clickable results sidebar.

## Scope

- **Single page only** — artworks are always page 1
- **Prepress QC checks:** bleed/trim safety, image resolution/DPI, color space (CMYK/RGB/spot), font embedding & rendering, overprint/knockout, transparency flattening
- **Packaging regulatory checks:** required text presence, barcode/UPC integrity, nutrition panel format, allergen warnings, recycling/disposal symbols, country of origin, legal disclaimers (R, TM)

## Architecture

**Approach: Unified AI Service** — extend the existing `AIAnalysisServiceProtocol` with a new `inspect()` method. Reuse `OpenRouterAIService` (same model, API key management, image encoding). New response model (`InspectionResult`) with located issues.

## Data Models

```swift
struct InspectionResult {
    let issues: [InspectionIssue]
    let summary: String                // One-paragraph overall assessment
}

struct InspectionIssue: Identifiable {
    let id: Int                        // Sequential: 1, 2, 3...
    let severity: IssueSeverity        // .pass, .warn, .fail
    let category: IssueCategory
    let title: String                  // Short: "No bleed detected"
    let detail: String                 // Full explanation
    let location: IssueLocation?       // nil for page-wide issues
}

struct IssueLocation {
    let x: Double                      // 0.0-1.0, from left
    let y: Double                      // 0.0-1.0, from top
    let w: Double                      // 0.0-1.0, width fraction
    let h: Double                      // 0.0-1.0, height fraction
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

## AI Service

### Protocol Extension

```swift
protocol AIAnalysisServiceProtocol: Sendable {
    // Existing
    func analyze(left:right:diff:leftText:rightText:diffResult:structuralDiff:) async throws -> AIAnalysisResult
    // New
    func inspect(image: NSImage, metadata: PDFMetadata, pageMetadata: PDFPageMetadata) async throws -> InspectionResult
}
```

### Input

- Page 1 rendered as JPEG (same encoding pipeline as compare: 0.8 quality, fallback to 0.6 if > 1MB)
- Text context from `PDFMetadata` (page count, color profiles, fonts) and `PDFPageMetadata` (text content, image count, dimensions)

### System Prompt

Instructs the model to act as a prepress QC inspector and packaging compliance analyst. Must return JSON with `issues` array and `summary`. Each issue has `id`, `severity`, `category`, `title`, `detail`, and nullable `location` (percentage-based bounding box).

### AI Response Format

```json
{
  "issues": [
    {
      "id": 1,
      "severity": "fail",
      "category": "bleed",
      "title": "No bleed area detected",
      "detail": "The artwork appears to have content ending exactly at the trim edge...",
      "location": { "x": 0.0, "y": 0.0, "w": 1.0, "h": 0.05 }
    }
  ],
  "summary": "3 issues found: 1 critical, 2 warnings. Artwork needs bleed extension..."
}
```

## UI — Canvas Pin Annotations

Upgrade the Inspector's page canvas from plain `ScrollView` to `ZoomableContainer` (already exists). Layer pin annotations on top in a `ZStack`.

### IssuePinView

- Small numbered circle at the center of the issue's bounding box
- Color by severity: red (fail), yellow (warn), green (pass)
- Shows issue number (1, 2, 3...)
- Fixed visual size — does not scale with zoom
- Tapping selects the pin, shows a popover with title + severity badge + detail + category
- Selected pin gets a subtle pulse animation

### Interaction

- Click pin on canvas -> sidebar scrolls to that issue, popover appears
- Click issue in sidebar -> canvas scrolls/zooms to pin location, pin highlights
- Bidirectional selection via shared `selectedIssueId` state

## UI — Right Sidebar (Inspection Results Panel)

Slides in from the right when inspection results arrive. Toggleable.

```
┌───────────────────────────────────────────────────────┐
│  [<] Page 1 of 1 [>]           [🔍 Inspect]          │
│ ┌─────────────────────────────┬─────────────────────┐ │
│ │                             │ INSPECTION RESULTS  │ │
│ │   PDF Page Canvas           │                     │ │
│ │                             │ Summary: 3 issues   │ │
│ │     ①  ②                    │ 1 fail, 2 warnings  │ │
│ │                             │─────────────────────│ │
│ │          ③                  │ ✗ #1 No bleed  FAIL │ │
│ │                             │   Artwork extends...│ │
│ │                             │─────────────────────│ │
│ │                             │ ⚠ #2 Low-res  WARN │ │
│ │                             │   Image at 150dpi...│ │
│ │                             │─────────────────────│ │
│ │                             │ ⚠ #3 Missing ® WARN│ │
│ │                             │   Brand name lacks..│ │
│ │                             │─────────────────────│ │
│ │                             │ [Copy Report] [Hide]│ │
│ └─────────────────────────────┴─────────────────────┘ │
│  Meta | Fonts | Images | Colors                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │ Title: MyArtwork.pdf   Author: Designer         │  │
│  └─────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────┘
```

### Contents

1. **Header** — "Inspection Results" title + issue count + severity breakdown
2. **Issue list** — scrollable, each row: severity icon, number, title, category tag, truncated detail. Click to select
3. **Expanded detail** — selected row expands to show full detail text
4. **Footer** — "Copy Report" (markdown), pin visibility toggle

### Trigger

"Inspect" toolbar button, requires API key (same check as compare). Progress spinner in sidebar while analyzing. Error state with retry.

## State Management

### InspectorViewModel Additions

```swift
// State
var inspectionResult: InspectionResult?
var isInspecting: Bool = false
var inspectionError: String?
var selectedIssueId: Int?           // bidirectional: pin <-> sidebar
var showInspectionSidebar: Bool = false
var showPins: Bool = true

// Method
func runInspection(apiKey: String) async
```

### Reset Behavior

- Results clear when the document changes
- Results persist across page navigation (they're always for page 1)
- Pins hidden when user navigates away from page 1

## Testing

- Unit tests for `InspectionResult` JSON parsing (valid, missing location, malformed)
- Unit tests for severity/category enum decoding
- `MockAIAnalysisService` extended with `inspect()` returning canned results
- `InspectorViewModel` tests: runInspection success/failure, state transitions, selectedIssueId bidirectional binding
- Pin position math: percentage * dimension (simple unit test)
