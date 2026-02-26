# UX Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire up all compare features behind a document-first navigation with tab-based Inspector/Compare switching, document drop slots, animated blink overlay, and multi-select sidebar.

**Architecture:** Hoist navigation state (activeTab, compareViewModel) to AppViewModel so both sidebar and detail area can interact with compare mode. Replace the current single-selection sidebar with multi-select. Add document drop slots to CompareView. Replace static OverlayView with animated blink.

**Tech Stack:** Swift/SwiftUI (macOS 14+), PDFKit for rendering

**Design doc:** `docs/plans/2026-02-26-ux-redesign-design.md`

---

### Task 1: Add navigation state and compare VM to AppViewModel

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift`

**Step 1: Add activeTab, selectedDocuments set, and compareViewModel**

Replace the entire file with:

```swift
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable @MainActor
final class AppViewModel {
    enum ActiveTab: String, CaseIterable {
        case inspector = "Inspector"
        case compare = "Compare"
    }

    var documents: [OpenedDocument] = []
    var selectedDocuments: Set<OpenedDocument> = []
    var activeTab: ActiveTab = .inspector
    var errorMessage: String?
    var isDropTargeted = false

    let pdfService: PDFServiceProtocol
    let compareViewModel: CompareViewModel

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
        self.compareViewModel = CompareViewModel(pdfService: pdfService)
    }

    /// The single selected document for inspector mode (first in selection set)
    var selectedDocument: OpenedDocument? {
        selectedDocuments.count == 1 ? selectedDocuments.first : nil
    }

    func openFiles(urls: [URL]) {
        let pdfUrls = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .prefix(10)

        var newDocs: [OpenedDocument] = []
        for url in pdfUrls {
            do {
                let doc = try pdfService.openDocument(path: url.path)
                documents.append(doc)
                newDocs.append(doc)
            } catch {
                errorMessage = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        // Auto-enter compare mode if exactly 2 new PDFs opened
        if newDocs.count == 2 {
            enterCompareMode(left: newDocs[0], right: newDocs[1])
        } else if newDocs.count == 1 && selectedDocuments.isEmpty {
            selectedDocuments = [newDocs[0]]
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let pdfProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }
        guard !pdfProviders.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in pdfProviders {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier),
                   let url = item as? URL {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                openFiles(urls: urls)
            }
        }
        return true
    }

    func enterCompareMode(left: OpenedDocument, right: OpenedDocument) {
        activeTab = .compare
        Task {
            await compareViewModel.setDocuments(left: left, right: right)
        }
    }

    func enterCompareModeFromSelection() {
        let sorted = documents.filter { selectedDocuments.contains($0) }
        guard sorted.count == 2 else { return }
        enterCompareMode(left: sorted[0], right: sorted[1])
    }

    func removeDocument(_ doc: OpenedDocument) {
        documents.removeAll { $0.id == doc.id }
        selectedDocuments.remove(doc)
        if compareViewModel.leftDocument == doc {
            compareViewModel.leftDocument = nil
        }
        if compareViewModel.rightDocument == doc {
            compareViewModel.rightDocument = nil
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | grep -E '(error:|BUILD)' | head -10`
Expected: BUILD SUCCEEDED (or errors from views that still reference old API — those get fixed in later tasks)

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift
git commit -m "refactor: add activeTab, multi-select, and compareViewModel to AppViewModel"
```

---

### Task 2: Add left/right document slot methods to CompareViewModel

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift`

**Step 1: Change default mode to overlay and add slot methods**

Replace the entire file with:

```swift
import Foundation
import AppKit

@Observable @MainActor
final class CompareViewModel {
    enum CompareMode: String, CaseIterable {
        case overlay = "Overlay"
        case sideBySide = "Side by Side"
        case swipe = "Swipe"
        case onionSkin = "Onion Skin"
    }

    var leftDocument: OpenedDocument?
    var rightDocument: OpenedDocument?
    var currentPage: UInt32 = 0
    var compareMode: CompareMode = .overlay
    var sensitivity: Float = 0.1
    var isComparing = false
    var errorMessage: String?

    var leftImage: NSImage?
    var rightImage: NSImage?
    var diffResult: PDFDiffResult?
    var structuralDiff: PDFStructuralDiffResult?

    let pdfService: PDFServiceProtocol

    init(pdfService: PDFServiceProtocol) {
        self.pdfService = pdfService
    }

    var maxPageCount: UInt32 {
        guard let left = leftDocument, let right = rightDocument else { return 0 }
        return min(left.pageCount, right.pageCount)
    }

    var hasDocuments: Bool {
        leftDocument != nil && rightDocument != nil
    }

    func setDocuments(left: OpenedDocument, right: OpenedDocument) async {
        self.leftDocument = left
        self.rightDocument = right
        self.currentPage = 0
        await renderAndDiff()
    }

    func setLeftDocument(_ doc: OpenedDocument) {
        leftDocument = doc
        if hasDocuments {
            currentPage = 0
            Task { await renderAndDiff() }
        }
    }

    func setRightDocument(_ doc: OpenedDocument) {
        rightDocument = doc
        if hasDocuments {
            currentPage = 0
            Task { await renderAndDiff() }
        }
    }

    func clearLeftDocument() {
        leftDocument = nil
        leftImage = nil
        diffResult = nil
        structuralDiff = nil
    }

    func clearRightDocument() {
        rightDocument = nil
        rightImage = nil
        diffResult = nil
        structuralDiff = nil
    }

    func swapDocuments() {
        let temp = leftDocument
        leftDocument = rightDocument
        rightDocument = temp
        let tempImg = leftImage
        leftImage = rightImage
        rightImage = tempImg
        if hasDocuments {
            Task { await renderAndDiff() }
        }
    }

    func nextPage() {
        guard maxPageCount > 0, currentPage < maxPageCount - 1 else { return }
        currentPage += 1
        Task { await renderAndDiff() }
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        Task { await renderAndDiff() }
    }

    func updateSensitivity(_ newValue: Float) {
        sensitivity = newValue
        Task { await computeDiff() }
    }

    func renderAndDiff() async {
        guard let left = leftDocument, let right = rightDocument else { return }
        isComparing = true
        defer { isComparing = false }

        do {
            let leftRendered = try pdfService.renderPage(document: left, page: currentPage, dpi: 150)
            let rightRendered = try pdfService.renderPage(document: right, page: currentPage, dpi: 150)
            self.leftImage = leftRendered.image
            self.rightImage = rightRendered.image
        } catch {
            self.errorMessage = error.localizedDescription
            return
        }

        await computeDiff()
    }

    private func computeDiff() async {
        guard let left = leftDocument, let right = rightDocument else { return }

        do {
            self.diffResult = try pdfService.computePixelDiff(
                left: left, right: right,
                page: currentPage, dpi: 150,
                sensitivity: sensitivity
            )
            self.structuralDiff = try pdfService.computeStructuralDiff(left: left, right: right)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

**Step 2: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift
git commit -m "refactor: overlay as default mode, add slot methods and swap to CompareViewModel"
```

---

### Task 3: Rewrite AppView with tab switching

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/AppView.swift`

**Step 1: Replace AppView with tab-based detail area**

Replace the entire file with:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            DetailAreaView(viewModel: viewModel)
        }
        .frame(minWidth: 900, minHeight: 650)
        .onDrop(of: [.pdf], isTargeted: $viewModel.isDropTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Detail Area

struct DetailAreaView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            if !viewModel.documents.isEmpty {
                tabBar
                Divider()
            }

            // Content
            switch viewModel.activeTab {
            case .inspector:
                if let selected = viewModel.selectedDocument {
                    DocumentDetailView(document: selected, pdfService: viewModel.pdfService)
                } else if viewModel.documents.isEmpty {
                    DropZoneView(viewModel: viewModel)
                } else {
                    Text("Select a document in the sidebar")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .compare:
                CompareView(viewModel: viewModel.compareViewModel)
            }
        }
    }

    private var tabBar: some View {
        HStack {
            Picker("", selection: Binding(
                get: { viewModel.activeTab },
                set: { viewModel.activeTab = $0 }
            )) {
                ForEach(AppViewModel.ActiveTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(viewModel.documents, selection: Binding(
                get: { viewModel.selectedDocuments },
                set: { viewModel.selectedDocuments = $0 }
            )) { doc in
                DocumentRow(document: doc)
                    .draggable(doc.path) // Enable drag from sidebar
            }
            .navigationTitle("Documents")

            // Compare button at bottom
            if viewModel.selectedDocuments.count == 2 {
                Divider()
                Button {
                    viewModel.enterCompareModeFromSelection()
                } label: {
                    Label("Compare Selected", systemImage: "square.split.2x1")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(12)
            }
        }
    }
}

struct DocumentRow: View {
    let document: OpenedDocument

    var body: some View {
        HStack {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.fileName)
                    .lineLimit(1)
                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Document Detail (Inspector)

struct DocumentDetailView: View {
    let document: OpenedDocument
    let pdfService: PDFServiceProtocol
    @State private var inspectorVM: InspectorViewModel?

    var body: some View {
        Group {
            if let vm = inspectorVM {
                InspectorView(viewModel: vm)
            } else {
                ProgressView()
            }
        }
        .task(id: document.id) {
            let vm = InspectorViewModel(pdfService: pdfService)
            await vm.loadDocument(document)
            inspectorVM = vm
        }
    }
}

// MARK: - Drop Zone

struct DropZoneView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop PDF files here")
                .font(.title2)
            Text("Or use File > Open to add documents")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(viewModel.isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

**Step 2: Build and verify**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | grep -E '(error:|BUILD)' | head -10`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/AppView.swift
git commit -m "feat: tab-based detail area with Inspector/Compare switching and multi-select sidebar"
```

---

### Task 4: Create document drop slot view

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift`

**Step 1: Create the drop slot component**

```swift
import SwiftUI

struct DocumentSlotView: View {
    let label: String
    let document: OpenedDocument?
    let onDrop: (String) -> Void
    let onClear: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let doc = document {
                // Filled slot
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .foregroundStyle(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.fileName)
                            .font(.body)
                            .lineLimit(1)
                        Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.08))
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            } else {
                // Empty slot
                VStack(spacing: 4) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Drop PDF here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                        )
                )
            }
        }
        .onDrop(of: [.plainText], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: String.self) { path, _ in
                    if let path {
                        DispatchQueue.main.async {
                            onDrop(path)
                        }
                    }
                }
            }
            return true
        }
    }
}
```

**Step 2: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift
git commit -m "feat: document drop slot component for compare mode"
```

---

### Task 5: Rewrite CompareView with document slots

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`

**Step 1: Replace CompareView with slots + visualization + bottom panel layout**

Replace the entire file with:

```swift
import SwiftUI

struct CompareView: View {
    @State var viewModel: CompareViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Document slots
            documentSlots
            Divider()

            if viewModel.hasDocuments {
                // Compare toolbar (mode picker, sensitivity, page nav)
                compareToolbar
                Divider()

                // Main content: visualization + diff summary
                VSplitView {
                    compareContent
                        .frame(minHeight: 300)

                    DiffSummaryPanel(
                        diffResult: viewModel.diffResult,
                        structuralDiff: viewModel.structuralDiff
                    )
                    .frame(minHeight: 120, idealHeight: 180, maxHeight: 300)
                }
            } else if viewModel.isComparing {
                ProgressView("Comparing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Drag documents into the slots above")
                        .foregroundStyle(.secondary)
                    Text("or select two in the sidebar and click Compare")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Document Slots

    private var documentSlots: some View {
        HStack(spacing: 12) {
            DocumentSlotView(
                label: "Left",
                document: viewModel.leftDocument,
                onDrop: { path in
                    if let doc = findDocument(path: path) {
                        viewModel.setLeftDocument(doc)
                    }
                },
                onClear: { viewModel.clearLeftDocument() }
            )

            Button {
                viewModel.swapDocuments()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.hasDocuments)

            DocumentSlotView(
                label: "Right",
                document: viewModel.rightDocument,
                onDrop: { path in
                    if let doc = findDocument(path: path) {
                        viewModel.setRightDocument(doc)
                    }
                },
                onClear: { viewModel.clearRightDocument() }
            )
        }
        .padding(12)
    }

    /// Look up an OpenedDocument by path from the service.
    /// The document must already be opened (present in the service's cache).
    private func findDocument(path: String) -> OpenedDocument? {
        try? viewModel.pdfService.openDocument(path: path)
    }

    // MARK: - Toolbar

    private var compareToolbar: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: $viewModel.compareMode) {
                ForEach(CompareViewModel.CompareMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)

            Spacer()

            HStack(spacing: 8) {
                Text("Sensitivity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { viewModel.sensitivity },
                    set: { viewModel.updateSensitivity($0) }
                ), in: 0.001...0.5)
                .frame(width: 120)
                Text(String(format: "%.1f%%", viewModel.sensitivity * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)
            }

            Divider().frame(height: 20)

            HStack(spacing: 8) {
                Button(action: { viewModel.previousPage() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentPage == 0)

                Text("Page \(viewModel.currentPage + 1) of \(viewModel.maxPageCount)")
                    .font(.body.monospacedDigit())

                Button(action: { viewModel.nextPage() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.maxPageCount == 0 || viewModel.currentPage >= viewModel.maxPageCount - 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Compare Content

    @ViewBuilder
    private var compareContent: some View {
        switch viewModel.compareMode {
        case .overlay:
            AnimatedOverlayView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage
            )
        case .sideBySide:
            SideBySideView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage,
                leftLabel: viewModel.leftDocument?.fileName,
                rightLabel: viewModel.rightDocument?.fileName
            )
        case .swipe:
            SwipeView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage
            )
        case .onionSkin:
            OnionSkinView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage
            )
        }
    }
}
```

**Step 2: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift
git commit -m "feat: CompareView with document drop slots and restructured layout"
```

---

### Task 6: Create animated blink overlay view

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift`

**Step 1: Create the animated blink view**

```swift
import SwiftUI

struct AnimatedOverlayView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?

    @State private var showingLeft = true
    @State private var isPlaying = true
    @State private var blinkInterval: Double = 0.8

    // Timer-driven animation
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Blink canvas
            ZStack {
                if showingLeft, let leftImage {
                    Image(nsImage: leftImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if !showingLeft, let rightImage {
                    Image(nsImage: rightImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text("No images to compare")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Blink controls
            blinkControls
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: isPlaying) { _, playing in
            if playing { startTimer() } else { stopTimer() }
        }
        .onChange(of: blinkInterval) { _, _ in
            if isPlaying {
                stopTimer()
                startTimer()
            }
        }
    }

    private var blinkControls: some View {
        HStack(spacing: 16) {
            // Play/Pause
            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .frame(width: 24)

            // Manual toggle (when paused)
            if !isPlaying {
                HStack(spacing: 4) {
                    Button {
                        showingLeft = true
                    } label: {
                        Text("Left")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(showingLeft ? Color.accentColor : Color.clear)
                            .foregroundStyle(showingLeft ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingLeft = false
                    } label: {
                        Text("Right")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(!showingLeft ? Color.accentColor : Color.clear)
                            .foregroundStyle(!showingLeft ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Speed control
            HStack(spacing: 8) {
                Text("Speed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $blinkInterval, in: 0.3...2.0)
                    .frame(width: 100)
                Text(String(format: "%.1fs", blinkInterval))
                    .font(.caption.monospacedDigit())
                    .frame(width: 30)
            }

            // Current side indicator
            Text(showingLeft ? "Left" : "Right")
                .font(.caption.bold())
                .foregroundStyle(showingLeft ? .blue : .orange)
                .frame(width: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: blinkInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                showingLeft.toggle()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
```

**Step 2: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift
git commit -m "feat: animated blink overlay for prepress comparison"
```

---

### Task 7: Clean up InspectorViewModel and old OverlayView

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/OverlayView.swift`

**Step 1: Remove unused Tab enum from InspectorViewModel**

In `InspectorViewModel.swift`, delete lines 14-15:

```swift
    enum Tab: String, CaseIterable { case inspector, compare, separations }
    var selectedTab: Tab = .inspector
```

**Step 2: Keep OverlayView as-is**

The old `OverlayView.swift` can stay in the project — it's no longer referenced by `CompareView` (which now uses `AnimatedOverlayView`), but it's harmless to keep as a static diff view that could be useful later.

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift
git commit -m "chore: remove unused Tab enum from InspectorViewModel"
```

---

### Task 8: Build, verify, and fix any compilation issues

**Files:**
- Possibly any file that has compilation issues

**Step 1: Build the full project**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | grep -E '(error:|BUILD)' | head -20`
Expected: BUILD SUCCEEDED

**Step 2: If there are errors, fix them**

Common issues to check:
- `CompareViewModelTests.swift` may reference old API — update `setDocuments` calls if needed
- Any reference to `SidebarContent` should now be `SidebarView`
- The `CompareView` now takes `@State var viewModel` but `AppView` passes `viewModel.compareViewModel` — verify this works

**Step 3: Launch the app and verify**

Run: `open $(xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff -showBuildSettings 2>/dev/null | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')/PdfDiff.app`

Verify:
- App launches with empty drop zone
- Cmd+O opens PDFs, they appear in sidebar
- Clicking one document shows Inspector view
- Cmd+clicking two documents shows "Compare Selected" button
- Clicking "Compare Selected" switches to Compare tab with both docs in slots
- Overlay blink animation plays
- Mode picker switches between all 4 compare views
- Diff summary panel shows at the bottom

**Step 4: Commit any fixes**

```bash
git add PdfDiffApp/
git commit -m "fix: resolve compilation issues from UX redesign"
```

---

### Task 9: Update tests for new API

**Files:**
- Modify: `PdfDiffApp/PdfDiffTests/ViewModels/CompareViewModelTests.swift`

**Step 1: Update tests to match new CompareViewModel API**

Replace the entire file with:

```swift
import Testing
@testable import PdfDiff

@Suite("CompareViewModel Tests")
@MainActor
struct CompareViewModelTests {
    let mockService = MockPDFService()

    @Test("sets documents and computes diff")
    func setsDocumentsAndDiffs() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)

        #expect(vm.leftDocument == left)
        #expect(vm.rightDocument == right)
        #expect(vm.leftImage != nil)
        #expect(vm.rightImage != nil)
        #expect(vm.diffResult != nil)
        #expect(vm.structuralDiff != nil)
    }

    @Test("page navigation syncs both sides")
    func pageNavigationSynced() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)
        #expect(vm.currentPage == 0)

        vm.nextPage()
        #expect(vm.currentPage == 1)

        vm.nextPage()
        #expect(vm.currentPage == 2)

        vm.nextPage()
        #expect(vm.currentPage == 2)

        vm.previousPage()
        #expect(vm.currentPage == 1)
    }

    @Test("does not go below page 0")
    func doesNotGoBelowZero() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)

        vm.previousPage()
        #expect(vm.currentPage == 0)
    }

    @Test("default compare mode is overlay")
    func defaultModeIsOverlay() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.compareMode == .overlay)
    }

    @Test("swap documents exchanges left and right")
    func swapDocuments() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)
        vm.swapDocuments()

        #expect(vm.leftDocument == right)
        #expect(vm.rightDocument == left)
    }

    @Test("set individual slot triggers diff when both filled")
    func setIndividualSlot() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        vm.setLeftDocument(left)
        #expect(vm.leftDocument == left)
        #expect(!vm.hasDocuments)

        vm.setRightDocument(right)
        #expect(vm.hasDocuments)
    }

    @Test("clear slot removes document")
    func clearSlot() async {
        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        let vm = CompareViewModel(pdfService: mockService)

        await vm.setDocuments(left: left, right: right)

        vm.clearLeftDocument()
        #expect(vm.leftDocument == nil)
        #expect(!vm.hasDocuments)
    }

    @Test("sensitivity update stores value")
    func sensitivityUpdate() async {
        let vm = CompareViewModel(pdfService: mockService)
        vm.updateSensitivity(0.05)
        #expect(vm.sensitivity == 0.05)
    }

    @Test("maxPageCount returns minimum of both documents")
    func maxPageCount() async {
        let vm = CompareViewModel(pdfService: mockService)
        #expect(vm.maxPageCount == 0)

        let left = try! mockService.openDocument(path: "/left.pdf")
        let right = try! mockService.openDocument(path: "/right.pdf")
        await vm.setDocuments(left: left, right: right)

        #expect(vm.maxPageCount == 3)
    }
}
```

**Step 2: Commit**

```bash
git add PdfDiffApp/PdfDiffTests/ViewModels/CompareViewModelTests.swift
git commit -m "test: update CompareViewModel tests for new slot API and overlay default"
```

---

## Execution Notes

**Build order:** Tasks 1-2 modify view models (no UI dependency). Task 3 rewrites AppView. Task 4 creates the slot component. Task 5 rewrites CompareView (depends on 4). Task 6 creates the blink view. Task 7 cleans up. Task 8 is the integration build/verify. Task 9 updates tests.

**XcodeGen:** After adding new files, regenerate the project: `cd PdfDiffApp && xcodegen generate` before building.

**MockPDFService note:** The `computePixelDiff` method returns hardcoded data. The animated overlay doesn't need diff results — it just blinks between left/right rendered images. The diff summary panel will show the mock data.

**Drag-and-drop:** The sidebar uses `.draggable(doc.path)` (plain text) and the slots use `.onDrop(of: [.plainText])` to receive the path string. The slot then calls `pdfService.openDocument(path:)` to get the `OpenedDocument`. Since MockPDFService caches by path, re-opening the same path returns a valid document.
