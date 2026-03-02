# Improvements Roadmap Design

## Priority 1: Test Coverage (Foundation)

**Goal:** Establish comprehensive Swift test coverage as a safety net for all future work.

### What exists
- 17 Rust tests (core engine, rendering, diff algorithms, preflight)
- 71 Swift tests across 6 suites (CompareViewModel, AIAnalysisService, KeychainHelper, SettingsManager, InspectionResult, InspectorViewModel)
- Zero UI/snapshot tests for the 21 view files

### What to add

**ViewModel Integration Tests:**
- InspectorViewModel: drawer state (toggle, dismiss, keyboard shortcuts), zoom, page navigation, inspection flow
- CompareViewModel: drawer state, document slot management (set, clear, swap), sensitivity, compare mode switching
- AppViewModel: tab switching, document management, selection, drop handling
- BatchViewModel: folder matching, results state

**Snapshot Tests (using swift-snapshot-testing):**
- All 21 view files at default state
- Key interactive states: drawer open, document loaded, comparison active, empty states
- Light + dark mode variants
- Generates reference images on first run, catches visual regressions after

**Service Tests:**
- BarcodeDetectionService mock tests
- ReportGenerator output validation
- RenderCache eviction behavior

### Architecture
- Add `swift-snapshot-testing` as SPM dependency in test target
- Create `PdfDiffSnapshotTests/` directory for snapshot tests
- Mock all services via existing protocol pattern (PDFServiceProtocol, AIAnalysisServiceProtocol)

---

## Priority 2: Async Rendering Pipeline

**Goal:** Background rendering with progressive loading for large PDFs.

- Replace synchronous `renderPage` calls with async Task-based pipeline
- Add render queue with priority (visible page first, adjacent pages prefetch)
- Cancellation support when user navigates away
- Progressive DPI: render at 72 DPI immediately, upgrade to 150 DPI in background
- Leverage existing LRU RenderCache (500MB cap)

---

## Priority 3: Undo/Redo System

**Goal:** macOS-standard undo/redo for document operations.

- Integrate with NSUndoManager via SwiftUI's @Environment(\.undoManager)
- Undoable actions: set/clear/swap document slots, change compare mode, change sensitivity, navigate pages
- Redo support for all undoable actions
- Menu integration: Edit > Undo/Redo with Cmd+Z/Cmd+Shift+Z

---

## Priority 4: CLI Tool

**Goal:** Command-line interface for CI/CD and automation workflows.

- Standalone binary using Rust core directly (no SwiftUI dependency)
- Commands: `compare`, `preflight`, `inspect`, `batch`
- Output formats: JSON, markdown, PDF report
- Exit codes for CI integration (0 = pass, 1 = differences found, 2 = error)
- Installable via `cargo install` or Homebrew tap
