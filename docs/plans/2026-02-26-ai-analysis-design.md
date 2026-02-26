# AI-Powered Analysis — Design

## Overview

Add AI-powered visual comparison and QC analysis to PDF Diff Desktop using OpenRouter. The feature is manually triggered via a single "Analyze with AI" button in the compare toolbar. All four analysis types run in a single API call and results display inline in the existing DiffSummaryPanel.

## Requirements

- OpenRouter integration with configurable API key stored in macOS Keychain
- Hardcoded model: `google/gemini-2.5-flash`
- Single "Analyze with AI" button triggers all analyses at once
- Four analysis types in one call:
  1. **Visual change description** — natural language summary of visual differences
  2. **Semantic text comparison** — meaningful description of text changes
  3. **Prepress QC checklist** — checks against common prepress rules
  4. **Anomaly detection** — unexpected or critical findings
- Results are ephemeral (in-memory) with a "Copy AI Report" button for clipboard export

## Architecture

### Approach: Swift-side networking

All OpenRouter API calls happen in Swift via `URLSession`. A new `AIAnalysisService` handles prompt construction, image encoding, and response parsing. This avoids adding async HTTP dependencies to the Rust core.

### Data sent to the model

- Left page render (JPEG, base64)
- Right page render (JPEG, base64)
- Diff bitmap (JPEG, base64)
- Extracted text from both pages
- Structured diff summary (similarity score, changed pixel count, region count, structural changes)

## Component Design

### 1. Settings Infrastructure

- `Settings` scene added to `PdfDiffApp.swift` (Cmd+, for free on macOS)
- `SettingsView` with an "AI" section:
  - `SecureField` for API key, stored in macOS Keychain via `Security.framework`
  - "Verify" button that makes a lightweight OpenRouter call to confirm the key
  - Status indicator: unconfigured / valid / invalid
- `SettingsManager` — `@Observable` class that reads/writes Keychain, exposes `apiKey: String?` and `isAPIKeyValid: Bool`
- Injected into the environment for app-wide access

### 2. AIAnalysisService

- `AIAnalysisServiceProtocol` with a single method:
  ```swift
  func analyze(
      left: NSImage, right: NSImage, diff: NSImage,
      leftText: String, rightText: String,
      diffResult: PDFDiffResult,
      structuralDiff: PDFStructuralDiffResult
  ) async throws -> AIAnalysisResult
  ```
- `OpenRouterAIService` implementation:
  - Constructs multimodal message with system prompt defining all four analysis roles
  - Encodes images as base64 JPEG (quality 0.8, reduced to 0.6 if > 1MB)
  - Sends to `https://openrouter.ai/api/v1/chat/completions`
  - Parses JSON response into `AIAnalysisResult`
- `MockAIAnalysisService` for testing/previews
- `AIAnalysisResult` struct:
  - `visualChanges: String`
  - `textComparison: String`
  - `qcChecklist: [QCCheckItem]` — each with `check`, `status` (pass/warn/fail), `detail`
  - `anomalies: String`

### 3. CompareViewModel Integration

- New properties: `aiResult: AIAnalysisResult?`, `isAnalyzing: Bool`, `aiError: String?`
- `func runAIAnalysis() async` gathers all inputs and calls the service
- `AIAnalysisService` injected alongside existing `PDFServiceProtocol`
- "Analyze with AI" button disabled when: no API key, no comparison run, or analysis in-flight
- Button in compare toolbar next to zoom controls
- In-flight analysis cancelled on navigation or new comparison via structured concurrency

### 4. AI Results UI

- New `DisclosureGroup` sections in `DiffSummaryPanel`:
  - "Visual Changes" — plain text
  - "Text Comparison" — plain text
  - "Prepress QC" — list with colored status icons (green/yellow/red)
  - "Anomalies" — plain text, warning background if non-empty
- Loading state: `ProgressView` with "Analyzing with AI..."
- Error state: inline message with "Retry" button
- "Copy AI Report" button copies all sections as formatted text to clipboard
- Results cleared on new comparison

### 5. Prompt Engineering

- Single system prompt: prepress/print QC expert role
- Model returns JSON with keys: `visual_changes`, `text_comparison`, `qc_checklist`, `anomalies`
- User message: three labeled images + extracted text + structured diff context
- QC checklist prompt enumerates: bleed/trim safety, text readability, barcode/QR integrity, color consistency, image resolution, font rendering, alignment/registration, unintended content changes
- Temperature: 0 (deterministic)
- max_tokens: ~2000
- Model instructed to say "No issues found" for clean sections

### 6. Error Handling

- **No API key**: button disabled, tooltip says "Set API key in Settings"
- **401 (invalid key)**: inline error, no retry
- **429 (rate limited)**: inline error with retry button
- **Network error / timeout**: inline error with retry, 60s URLSession timeout
- **Malformed JSON response**: fall back to displaying raw text
- **Large pages**: JPEG quality reduced from 0.8 to 0.6 if > 1MB
- **Cancellation**: structured concurrency handles cleanup, no stale results
