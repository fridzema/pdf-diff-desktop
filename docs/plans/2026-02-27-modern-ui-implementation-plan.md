# Liquid Glass Modern UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Modernize all 21 SwiftUI views using macOS Tahoe's Liquid Glass design language, replace VSplitView panels with overlay drawers, and introduce a design token system for visual consistency.

**Architecture:** Glass effects on navigation layer (toolbar, tabs, sidebar). Canvas-first layout with on-demand glass overlay drawers replacing stacked VSplitView panels. Centralized DesignTokens enum for spacing, colors, typography, and animation. No functional changes — purely visual and layout.

**Tech Stack:** SwiftUI (macOS 26 / Tahoe), Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `glassEffectID`, `ToolbarSpacer`), `@Observable` ViewModels.

**Design doc:** `docs/plans/2026-02-27-modern-ui-design.md`

---

## Phase 1: Foundation

### Task 1: Update deployment target to macOS 26

**Files:**
- Modify: `PdfDiffApp/project.yml`

**Step 1: Update project.yml deployment target**

Change both `deploymentTarget.macOS` and `MACOSX_DEPLOYMENT_TARGET` and `LSMinimumSystemVersion` from `"14.0"` to `"26.0"`. Also update `SWIFT_VERSION` from `"5.10"` to `"6.0"` and `xcodeVersion` to `"26.0"`.

```yaml
options:
  bundleIdPrefix: com.pdfdiff
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "26.0"
```

And in the `settings.base` section:
```yaml
MACOSX_DEPLOYMENT_TARGET: "26.0"
SWIFT_VERSION: "6.0"
```

And in `info.properties`:
```yaml
LSMinimumSystemVersion: "26.0"
```

**Step 2: Regenerate Xcode project**

Run: `cd PdfDiffApp && xcodegen generate`
Expected: Project generated successfully.

**Step 3: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/project.yml PdfDiffApp/PdfDiff.xcodeproj
git commit -m "chore: update deployment target to macOS 26 for Liquid Glass support"
```

---

### Task 2: Create DesignTokens

**Files:**
- Create: `PdfDiffApp/PdfDiff/DesignTokens.swift`

**Step 1: Create the DesignTokens file**

```swift
import SwiftUI

enum DesignTokens {
    // MARK: - Spacing (8pt grid)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    // MARK: - Semantic Status Colors
    enum Status {
        static let pass = Color.green
        static let warn = Color.orange
        static let fail = Color.red
        static let info = Color.blue
    }

    // MARK: - Typography
    enum Typo {
        static let toolbarLabel = Font.caption
        static let sectionHeader = Font.headline
        static let bodyMono = Font.body.monospacedDigit()
        static let metric = Font.system(.title3, design: .rounded).monospacedDigit()
    }

    // MARK: - Animation
    enum Motion {
        static let snappy = Animation.snappy(duration: 0.25)
        static let smooth = Animation.smooth(duration: 0.35)
        static let bouncy = Animation.bouncy(duration: 0.4)
    }

    // MARK: - Canvas Background
    enum Canvas {
        static let darkBackground = Color(white: 0.08)
        static let lightBackground = Color(white: 0.96)
    }

    // MARK: - Drawer
    enum Drawer {
        static let maxHeightRatio: CGFloat = 0.4
        static let cornerRadius: CGFloat = 14
        static let horizontalPadding: CGFloat = 16
    }

    // MARK: - Severity Helpers

    static func severityColor(_ severity: PreflightCheckSeverity) -> Color {
        switch severity {
        case .pass: Status.pass
        case .warn: Status.warn
        case .fail: Status.fail
        case .info: Status.info
        }
    }

    static func severityIcon(_ severity: PreflightCheckSeverity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    static func issueSeverityColor(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .pass: Status.pass
        case .warn: Status.warn
        case .fail: Status.fail
        }
    }

    static func issueSeverityIcon(_ severity: IssueSeverity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    static func similarityColor(_ score: Double) -> Color {
        if score >= 0.99 { return Status.pass }
        if score >= 0.90 { return Status.warn }
        return Status.fail
    }

    static func qcStatusColor(_ status: QCStatus) -> Color {
        switch status {
        case .pass: Status.pass
        case .warn: Status.warn
        case .fail: Status.fail
        }
    }

    static func qcStatusIcon(_ status: QCStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }
}
```

**Step 2: Verify build**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/DesignTokens.swift
git commit -m "feat: add centralized DesignTokens for spacing, colors, typography, and animation"
```

---

## Phase 2: GlassDrawer Component

### Task 3: Create reusable GlassDrawer overlay component

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Components/GlassDrawer.swift`

**Step 1: Create the GlassDrawer component**

This is the reusable bottom overlay drawer with glass backdrop. It slides up from the bottom of its parent, overlays (not pushes) the content behind it, and caps at 40% parent height.

```swift
import SwiftUI

/// Reusable bottom overlay drawer with Liquid Glass backdrop.
/// Slides up from the bottom of its parent, overlaying canvas content.
struct GlassDrawer<Content: View>: View {
    let isPresented: Bool
    let content: Content

    @Namespace private var drawerNamespace

    init(isPresented: Bool, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        if isPresented {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)

                    ScrollView {
                        content
                            .padding(.horizontal, DesignTokens.Drawer.horizontalPadding)
                            .padding(.bottom, DesignTokens.Spacing.md)
                    }
                }
                .frame(maxHeight: UIConstants.drawerMaxHeight)
                .glassEffect(.regular, in: UnevenRoundedRectangle(
                    topLeadingRadius: DesignTokens.Drawer.cornerRadius,
                    topTrailingRadius: DesignTokens.Drawer.cornerRadius
                ))
                .padding(.horizontal, DesignTokens.Spacing.sm)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private enum UIConstants {
        // We use GeometryReader at call site to compute 40% max; here provide a reasonable default
        static let drawerMaxHeight: CGFloat = 400
    }
}

/// Variant that reads the parent's geometry to compute 40% max height.
struct GeometricGlassDrawer<Content: View>: View {
    let isPresented: Bool
    let content: Content

    init(isPresented: Bool, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            GlassDrawerInner(
                isPresented: isPresented,
                maxHeight: geo.size.height * DesignTokens.Drawer.maxHeightRatio,
                content: { content }
            )
        }
    }
}

private struct GlassDrawerInner<Content: View>: View {
    let isPresented: Bool
    let maxHeight: CGFloat
    let content: Content

    init(isPresented: Bool, maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        if isPresented {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)

                    ScrollView {
                        content
                            .padding(.horizontal, DesignTokens.Drawer.horizontalPadding)
                            .padding(.bottom, DesignTokens.Spacing.md)
                    }
                }
                .frame(maxHeight: maxHeight)
                .glassEffect(.regular, in: UnevenRoundedRectangle(
                    topLeadingRadius: DesignTokens.Drawer.cornerRadius,
                    topTrailingRadius: DesignTokens.Drawer.cornerRadius
                ))
                .padding(.horizontal, DesignTokens.Spacing.sm)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
```

**Note:** `UnevenRoundedRectangle` is available in macOS 14+. `glassEffect` requires macOS 26. If `glassEffect` is not available yet in the Xcode beta, use `.background(.ultraThinMaterial, in: UnevenRoundedRectangle(...))` as a fallback and add a `// TODO: Replace with glassEffect when available` comment.

**Step 2: Verify build**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Components/GlassDrawer.swift
git commit -m "feat: add reusable GlassDrawer overlay component with glass backdrop"
```

---

## Phase 3: Glass Navigation Shell

### Task 4: AppView glass tab picker and sidebar improvements

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/AppView.swift:30-87` (DetailAreaView and SidebarView)

**Step 1: Update the tab bar in DetailAreaView**

Replace the current `tabBar` computed property. Wrap the picker in a `GlassEffectContainer`, center it, and use design tokens for spacing.

Replace `DetailAreaView.tabBar` (lines 69-86) with:

```swift
private var tabBar: some View {
    GlassEffectContainer {
        HStack {
            Spacer()
            Picker("", selection: Binding(
                get: { viewModel.activeTab },
                set: { viewModel.activeTab = $0 }
            )) {
                ForEach(AppViewModel.ActiveTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            Spacer()
        }
    }
    .padding(.horizontal, DesignTokens.Spacing.md)
    .padding(.vertical, DesignTokens.Spacing.sm)
}
```

**Step 2: Update SidebarView for taller rows**

In `DocumentRow` (lines 122-138), increase spacing and add a minimum row height:

```swift
struct DocumentRow: View {
    let document: OpenedDocument

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(document.fileName)
                    .lineLimit(1)
                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")")
                    .font(DesignTokens.Typo.toolbarLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 36)
    }
}
```

**Step 3: Update DropZoneView with glass treatment**

Replace the `DropZoneView` body (lines 168-181) to use glass:

```swift
var body: some View {
    VStack(spacing: DesignTokens.Spacing.lg) {
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
    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
}
```

**Step 4: Update compare button padding in SidebarView**

Replace `.padding(12)` on the compare button (line 116) with `.padding(DesignTokens.Spacing.md)`.

**Step 5: Verify build**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/AppView.swift
git commit -m "feat: glass tab picker, improved sidebar rows, design tokens in AppView"
```

---

## Phase 4: Inspector Panel Redesign

### Task 5: Add drawer state to InspectorViewModel

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift`

**Step 1: Add drawer enum and state**

Add after the `showPins` property (line 23):

```swift
// Drawer state
enum DrawerPanel: String, CaseIterable {
    case metadata, preflight, inspection
}
var activeDrawer: DrawerPanel? = nil
var preflightResult: SwiftPreflightResult? = nil

func toggleDrawer(_ panel: DrawerPanel) {
    withAnimation(DesignTokens.Motion.snappy) {
        activeDrawer = activeDrawer == panel ? nil : panel
    }
}

func dismissDrawer() {
    withAnimation(DesignTokens.Motion.snappy) {
        activeDrawer = nil
    }
}
```

**Step 2: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run existing tests**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff 2>&1 | grep -E "(Test Suite|Test Case|Passed|Failed)" | tail -20`
Expected: All existing tests pass.

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/InspectorViewModel.swift
git commit -m "feat: add drawer panel state to InspectorViewModel"
```

---

### Task 6: Rewrite InspectorView with full-height canvas and drawer toggles

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`

**Step 1: Replace the full InspectorView body**

The key changes:
- Remove `VSplitView`
- Canvas takes full height
- Toolbar gets drawer toggle buttons on the right side
- Glass overlay drawers replace stacked panels
- Use `ToolbarSpacer` if available, otherwise standard `Spacer`

Replace the entire `body` and `toolbar` with:

```swift
var body: some View {
    VStack(spacing: 0) {
        toolbar
        Divider()

        // Full-height canvas with overlay drawers
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                pageCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Inspection sidebar (right-side glass overlay)
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

            // Bottom overlay drawer
            GeometricGlassDrawer(isPresented: viewModel.activeDrawer != nil) {
                drawerContent
            }
            .animation(DesignTokens.Motion.snappy, value: viewModel.activeDrawer)
        }
    }
    .frame(minHeight: 300)
    .animation(DesignTokens.Motion.snappy, value: viewModel.showInspectionSidebar)
    .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in viewModel.zoomIn() }
    .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in viewModel.zoomOut() }
    .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in viewModel.zoomFit() }
    .onKeyPress(.escape) {
        if viewModel.activeDrawer != nil {
            viewModel.dismissDrawer()
            return .handled
        }
        return .ignored
    }
}

@ViewBuilder
private var drawerContent: some View {
    switch viewModel.activeDrawer {
    case .metadata:
        MetadataPanel(metadata: viewModel.metadata, pageMetadata: viewModel.pagesMetadata)
    case .preflight:
        if let result = viewModel.preflightResult {
            PreflightPanel(result: result, onNavigateToPage: { page in
                viewModel.currentPage = page
            })
        } else {
            Text("No preflight results")
                .foregroundStyle(.secondary)
                .padding(DesignTokens.Spacing.lg)
        }
    case .inspection:
        if let result = viewModel.inspectionResult {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("AI Inspection")
                    .font(DesignTokens.Typo.sectionHeader)
                Text(result.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No inspection results")
                .foregroundStyle(.secondary)
                .padding(DesignTokens.Spacing.lg)
        }
    case nil:
        EmptyView()
    }
}
```

**Step 2: Update the toolbar to include drawer toggles**

Replace the `toolbar` computed property with:

```swift
private var toolbar: some View {
    HStack(spacing: DesignTokens.Spacing.sm) {
        // Page navigation
        Button(action: { viewModel.previousPage() }) {
            Image(systemName: "chevron.left")
        }
        .disabled(viewModel.currentPage == 0)

        Text("Page \(viewModel.currentPage + 1) of \(viewModel.document?.pageCount ?? 0)")
            .font(DesignTokens.Typo.bodyMono)

        Button(action: { viewModel.nextPage() }) {
            Image(systemName: "chevron.right")
        }
        .disabled(viewModel.currentPage >= (viewModel.document?.pageCount ?? 1) - 1)

        Divider().frame(height: 20)

        ZoomToolbar(
            zoomLevel: $viewModel.zoomLevel,
            onZoomIn: { viewModel.zoomIn() },
            onZoomOut: { viewModel.zoomOut() },
            onZoomFit: { viewModel.zoomFit() }
        )

        Spacer()

        // Inspection status/controls
        if viewModel.isInspecting {
            ProgressView()
                .controlSize(.small)
            Text("Inspecting...")
                .font(DesignTokens.Typo.toolbarLabel)
                .foregroundStyle(.secondary)
        } else if let error = viewModel.inspectionError {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Status.warn)
            Text(error)
                .font(DesignTokens.Typo.toolbarLabel)
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

        Button {
            if let key = settingsManager?.apiKey, !key.isEmpty {
                Task { await viewModel.runInspection(apiKey: key) }
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                Text("Inspect")
            }
        }
        .disabled(!viewModel.canRunInspection || settingsManager?.hasAPIKey != true)
        .help(settingsManager?.hasAPIKey != true ? "Set API key in Settings (\u{2318},)" : "Run AI inspection")

        Divider().frame(height: 20)

        // Drawer toggle buttons
        drawerToggle(.metadata, icon: "info.circle", label: "Metadata")
        drawerToggle(.preflight, icon: "checkmark.shield", label: "Preflight")

        if viewModel.inspectionResult != nil {
            drawerToggle(.inspection, icon: "wand.and.stars", label: "AI Results")
        }

        if viewModel.inspectionResult != nil && !viewModel.showInspectionSidebar {
            Button {
                viewModel.showInspectionSidebar = true
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Show inspection sidebar")
        }
    }
    .padding(.horizontal, DesignTokens.Spacing.md)
    .padding(.vertical, DesignTokens.Spacing.sm)
}

private func drawerToggle(_ panel: InspectorViewModel.DrawerPanel, icon: String, label: String) -> some View {
    Button {
        viewModel.toggleDrawer(panel)
    } label: {
        Image(systemName: icon)
    }
    .help(label)
    .foregroundStyle(viewModel.activeDrawer == panel ? Color.accentColor : .secondary)
}
```

**Step 3: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift
git commit -m "feat: rewrite InspectorView with full-height canvas and glass overlay drawers"
```

---

### Task 7: Apply design tokens to MetadataPanel and PreflightPanel

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/MetadataPanel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/PreflightPanel.swift`

**Step 1: Update MetadataPanel spacing**

In `MetadataPanel.swift`:
- Replace `.padding(8)` (lines 18, 34) with `.padding(DesignTokens.Spacing.sm)`
- Replace `.font(.caption)` on the picker tab with `.font(DesignTokens.Typo.toolbarLabel)` (if desired, optional since `.caption` is the same)

**Step 2: Update PreflightPanel to use DesignTokens**

In `PreflightPanel.swift`:
- Replace `.foregroundStyle(.green)` (lines 49, 104) with `.foregroundStyle(DesignTokens.Status.pass)`
- Replace `.foregroundStyle(.orange)` (lines 52, 107) with `.foregroundStyle(DesignTokens.Status.warn)`
- Replace `.foregroundStyle(.red)` (lines 55, 108) with `.foregroundStyle(DesignTokens.Status.fail)`
- Replace `.foregroundStyle(.blue)` (lines 58, 110) with `.foregroundStyle(DesignTokens.Status.info)`
- Replace `.padding(.horizontal, 12)` (lines 30, 62) with `.padding(.horizontal, DesignTokens.Spacing.md)`
- Replace `.padding(.vertical, 8)` (line 63) with `.padding(.vertical, DesignTokens.Spacing.sm)`
- Replace `.padding(.horizontal, 8)` (line 91) with `.padding(.horizontal, DesignTokens.Spacing.sm)`
- Replace `.font(.headline)` (line 42) with `.font(DesignTokens.Typo.sectionHeader)`
- Replace the `severityDot` function to use `DesignTokens.severityColor` and `DesignTokens.severityIcon`:

```swift
@ViewBuilder
private func severityDot(_ severity: PreflightCheckSeverity) -> some View {
    Image(systemName: DesignTokens.severityIcon(severity))
        .foregroundStyle(DesignTokens.severityColor(severity))
}
```

**Step 3: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/MetadataPanel.swift PdfDiffApp/PdfDiff/Views/Inspector/PreflightPanel.swift
git commit -m "refactor: apply DesignTokens to MetadataPanel and PreflightPanel"
```

---

## Phase 5: Compare Panel Redesign

### Task 8: Add drawer state to CompareViewModel

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift`

**Step 1: Add drawer state**

Add after `var panOffset: CGSize = .zero` (line 41):

```swift
// Drawer state
enum DrawerPanel: String, CaseIterable {
    case diffSummary, aiAnalysis
}
var activeDrawer: DrawerPanel? = nil

func toggleDrawer(_ panel: DrawerPanel) {
    withAnimation(DesignTokens.Motion.snappy) {
        activeDrawer = activeDrawer == panel ? nil : panel
    }
}

func dismissDrawer() {
    withAnimation(DesignTokens.Motion.snappy) {
        activeDrawer = nil
    }
}
```

**Step 2: Verify build and test**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift
git commit -m "feat: add drawer panel state to CompareViewModel"
```

---

### Task 9: Rewrite CompareView with full-height canvas and glass drawer

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`

**Step 1: Replace the body**

The key changes:
- Remove `VSplitView` wrapper around `compareContent` + `DiffSummaryPanel`
- Compare content takes full remaining height
- DiffSummaryPanel becomes a bottom overlay drawer
- Add drawer toggle button to toolbar

Replace the `body` (lines 9-65) with:

```swift
var body: some View {
    VStack(spacing: 0) {
        // Document slots
        documentSlots
        Divider()

        if viewModel.hasDocuments {
            // Compare toolbar
            compareToolbar
            Divider()

            // Full-height compare content with overlay drawer
            ZStack(alignment: .bottom) {
                compareContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                GeometricGlassDrawer(isPresented: viewModel.activeDrawer != nil) {
                    compareDrawerContent
                }
                .animation(DesignTokens.Motion.snappy, value: viewModel.activeDrawer)
            }
        } else if viewModel.isComparing {
            ProgressView("Comparing...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Drag documents into the slots above")
                    .foregroundStyle(.secondary)
                Text("or select two in the sidebar and click Compare")
                    .font(DesignTokens.Typo.toolbarLabel)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in viewModel.zoomIn() }
    .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in viewModel.zoomOut() }
    .onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in viewModel.zoomFit() }
    .onKeyPress(.escape) {
        if viewModel.activeDrawer != nil {
            viewModel.dismissDrawer()
            return .handled
        }
        return .ignored
    }
}
```

**Step 2: Add drawer content builder**

Add this new computed property:

```swift
@ViewBuilder
private var compareDrawerContent: some View {
    switch viewModel.activeDrawer {
    case .diffSummary:
        DiffSummaryPanel(
            diffResult: viewModel.diffResult,
            structuralDiff: viewModel.structuralDiff,
            aiResult: viewModel.aiResult,
            isAnalyzing: viewModel.isAnalyzing,
            aiError: viewModel.aiError,
            onRetry: {
                if let key = settingsManager?.apiKey, !key.isEmpty {
                    Task { await viewModel.runAIAnalysis(apiKey: key) }
                }
            }
        )
    case .aiAnalysis:
        if let ai = viewModel.aiResult {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("AI Analysis")
                    .font(DesignTokens.Typo.sectionHeader)
                Text(ai.visualChanges)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } else if viewModel.isAnalyzing {
            HStack {
                ProgressView().controlSize(.small)
                Text("Analyzing...")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No AI analysis results")
                .foregroundStyle(.secondary)
                .padding(DesignTokens.Spacing.lg)
        }
    case nil:
        EmptyView()
    }
}
```

**Step 3: Update compareToolbar to include drawer toggle**

At the end of the toolbar `HStack` (before the page navigation divider at line 172), add a drawer toggle. Replace the full `compareToolbar` with:

```swift
private var compareToolbar: some View {
    HStack(spacing: DesignTokens.Spacing.lg) {
        Picker("Mode", selection: $viewModel.compareMode) {
            ForEach(CompareViewModel.CompareMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 400)

        Spacer()

        HStack(spacing: DesignTokens.Spacing.sm) {
            Text("Sensitivity")
                .font(DesignTokens.Typo.toolbarLabel)
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

        // Zoom controls
        HStack(spacing: DesignTokens.Spacing.xs) {
            Button(action: { viewModel.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Text(String(format: "%.0f%%", viewModel.zoomLevel * 100))
                .font(.caption.monospacedDigit())
                .frame(width: 44)
                .onTapGesture { viewModel.zoomFit() }

            Button(action: { viewModel.zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Button("Fit") { viewModel.zoomFit() }
                .font(DesignTokens.Typo.toolbarLabel)
                .buttonStyle(.borderless)
        }

        Divider().frame(height: 20)

        Button {
            if let key = settingsManager?.apiKey, !key.isEmpty {
                Task { await viewModel.runAIAnalysis(apiKey: key) }
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                Text("Analyze")
            }
        }
        .disabled(!viewModel.canRunAIAnalysis || settingsManager?.hasAPIKey != true)
        .help(settingsManager?.hasAPIKey != true ? "Set API key in Settings (\u{2318},)" : "Run AI analysis")

        Divider().frame(height: 20)

        // Drawer toggle
        Button {
            viewModel.toggleDrawer(.diffSummary)
        } label: {
            Image(systemName: "chart.bar.doc.horizontal")
        }
        .help("Diff Summary")
        .foregroundStyle(viewModel.activeDrawer == .diffSummary ? Color.accentColor : .secondary)

        Divider().frame(height: 20)

        HStack(spacing: DesignTokens.Spacing.sm) {
            Button(action: { viewModel.previousPage() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.currentPage == 0)

            Text("Page \(viewModel.currentPage + 1) of \(viewModel.maxPageCount)")
                .font(DesignTokens.Typo.bodyMono)

            Button(action: { viewModel.nextPage() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.maxPageCount == 0 || viewModel.currentPage >= viewModel.maxPageCount - 1)
        }
    }
    .padding(.horizontal, DesignTokens.Spacing.md)
    .padding(.vertical, DesignTokens.Spacing.sm)
}
```

**Step 4: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift
git commit -m "feat: rewrite CompareView with full-height canvas and glass overlay drawer"
```

---

### Task 10: Apply design tokens to DiffSummaryPanel

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/DiffSummaryPanel.swift`

**Step 1: Replace hardcoded colors with DesignTokens**

Throughout the file:
- Replace `similarityColor` helper function with `DesignTokens.similarityColor`
- Replace `qcStatusIcon` with `DesignTokens.qcStatusIcon`
- Replace `qcStatusColor` with `DesignTokens.qcStatusColor`
- Replace `.foregroundStyle(.red)` on left values with `.foregroundStyle(DesignTokens.Status.fail)`
- Replace `.foregroundStyle(.green)` on right values with `.foregroundStyle(DesignTokens.Status.pass)`
- Replace `.foregroundStyle(.orange)` with `.foregroundStyle(DesignTokens.Status.warn)`
- Replace `.font(.headline)` with `.font(DesignTokens.Typo.sectionHeader)` on section labels
- Replace `.padding(12)` (line 108) with `.padding(DesignTokens.Spacing.md)`
- Replace `background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))` with `background(DesignTokens.Status.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))`

**Step 2: Remove the now-unused local helper functions**

Delete `similarityColor`, `qcStatusIcon`, `qcStatusColor` at the bottom of the file (lines 311-412), replacing their call sites with the `DesignTokens` equivalents.

**Step 3: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/DiffSummaryPanel.swift
git commit -m "refactor: apply DesignTokens to DiffSummaryPanel, remove local color helpers"
```

---

## Phase 6: Glass Document Slots

### Task 11: Glass DocumentSlotView

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift`

**Step 1: Update the filled slot to use glass**

Replace the filled slot (lines 20-47) with:

```swift
if let doc = document {
    HStack(spacing: DesignTokens.Spacing.sm) {
        Image(systemName: "doc.richtext")
            .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(doc.fileName)
                .font(.body)
                .lineLimit(1)
            Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                .font(DesignTokens.Typo.toolbarLabel)
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
    .padding(DesignTokens.Spacing.md)
    .glassEffect(.regular.tint(.accentColor), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
}
```

**Step 2: Update the empty slot to use glass**

Replace the empty slot (lines 49-81) with:

```swift
else {
    VStack(spacing: DesignTokens.Spacing.xs) {
        Image(systemName: "arrow.down.doc")
            .font(.title3)
            .foregroundStyle(.secondary)
        Text("Drop PDF here")
            .font(DesignTokens.Typo.toolbarLabel)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 60)
    .glassEffect(
        isTargeted ? .regular.tint(.accentColor) : .clear,
        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
    )
    .overlay {
        if dropSucceeded {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(DesignTokens.Status.pass)
                .transition(.scale.combined(with: .opacity))
        }
        if dropFailed {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundStyle(DesignTokens.Status.fail)
                .transition(.scale.combined(with: .opacity))
        }
    }
    .animation(DesignTokens.Motion.bouncy, value: isTargeted)
    .animation(DesignTokens.Motion.snappy, value: dropSucceeded)
    .animation(DesignTokens.Motion.snappy, value: dropFailed)
    .scaleEffect(isTargeted ? 1.02 : 1.0)
}
```

**Step 3: Update the spacing and label**

Replace `.padding(12)` on the document slots container in `CompareView.documentSlots` (if not already done) with `.padding(DesignTokens.Spacing.md)`.

Replace `VStack(spacing: 6)` at the top of `DocumentSlotView.body` (line 15) with `VStack(spacing: DesignTokens.Spacing.sm)`.

**Step 4: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Note:** If `glassEffect` is not available yet in the current Xcode beta, replace `.glassEffect(...)` calls with `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))` and add `// TODO: Replace with glassEffect when Xcode 26 beta supports it`.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift
git commit -m "feat: glass-backed document slots with tinted drop feedback"
```

---

## Phase 7: Component & Sub-View Token Migration

### Task 12: Apply tokens to ZoomToolbar and ZoomableContainer

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Components/ZoomToolbar.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Components/ZoomableContainer.swift`

**Step 1: Update ZoomToolbar**

Replace `HStack(spacing: 4)` with `HStack(spacing: DesignTokens.Spacing.xs)`.
Replace `.font(.caption.monospacedDigit())` on the zoom text with `.font(DesignTokens.Typo.toolbarLabel.monospacedDigit())`.
Replace the "Fit" button `.font(.caption)` with `.font(DesignTokens.Typo.toolbarLabel)`.

**Step 2: Update ZoomableContainer double-tap animation**

In `ZoomableContainer.swift`, replace `.easeInOut(duration: 0.25)` (line 94) with `DesignTokens.Motion.snappy`.
Replace `.easeOut(duration: 0.2)` (line 128) with `DesignTokens.Motion.snappy`.

**Step 3: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Components/ZoomToolbar.swift PdfDiffApp/PdfDiff/Views/Components/ZoomableContainer.swift
git commit -m "refactor: apply DesignTokens to ZoomToolbar and ZoomableContainer"
```

---

### Task 13: Apply tokens to compare sub-views

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/SideBySideView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/SwipeView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/OnionSkinView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/DiffOverlayView.swift`

**Step 1: AnimatedOverlayView**

- Replace `.padding(.horizontal, 12)` with `.padding(.horizontal, DesignTokens.Spacing.md)` (line 117)
- Replace `.padding(.vertical, 8)` with `.padding(.vertical, DesignTokens.Spacing.sm)` (line 118)
- Replace `Color(nsColor: .controlBackgroundColor)` background with `.background(.bar)` (the Tahoe-native toolbar material)
- Replace `.font(.caption)` on labels with `.font(DesignTokens.Typo.toolbarLabel)`
- Replace `.font(.caption.monospacedDigit())` with `.font(DesignTokens.Typo.toolbarLabel.monospacedDigit())`
- Replace `HStack(spacing: 16)` with `HStack(spacing: DesignTokens.Spacing.lg)` (line 56)

**Step 2: SideBySideView**

- Replace `Color(nsColor: .controlBackgroundColor)` with `.background(.bar)` (line 61)
- Replace `.font(.caption)` on labels with `.font(DesignTokens.Typo.toolbarLabel)` (lines 34, 38)
- Replace `.foregroundStyle(.orange)` on the unlock icon with `.foregroundStyle(DesignTokens.Status.warn)` (line 39)

**Step 3: SwipeView**

- Replace `.ultraThinMaterial` on labels with `.bar` (lines 67, 75)
- Replace `RoundedRectangle(cornerRadius: 4)` with `RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)` (lines 68, 76)
- Replace `.font(.caption)` with `.font(DesignTokens.Typo.toolbarLabel)` (lines 64, 72)

**Step 4: OnionSkinView**

- Replace `.padding(.horizontal, 12)` with `.padding(.horizontal, DesignTokens.Spacing.md)` (line 48)
- Replace `.padding(.vertical, 8)` with `.padding(.vertical, DesignTokens.Spacing.sm)` (line 49)
- Replace `Color(nsColor: .controlBackgroundColor)` with `.background(.bar)` (line 50)
- Replace `.font(.caption)` with `.font(DesignTokens.Typo.toolbarLabel)` (lines 37, 44)
- Replace `HStack(spacing: 12)` with `HStack(spacing: DesignTokens.Spacing.md)` (line 35)

**Step 5: DiffOverlayView**

- Replace `.padding(.horizontal, 12)` with `.padding(.horizontal, DesignTokens.Spacing.md)` (line 53)
- Replace `.padding(.vertical, 8)` with `.padding(.vertical, DesignTokens.Spacing.sm)` (line 54)
- Replace `Color(nsColor: .controlBackgroundColor)` with `.background(.bar)` (line 55)
- Replace `.font(.caption)` with `.font(DesignTokens.Typo.toolbarLabel)` on control labels (lines 42, 46)
- Replace `HStack(spacing: 16)` with `HStack(spacing: DesignTokens.Spacing.lg)` (line 36)
- Replace `HStack(spacing: 8)` with `HStack(spacing: DesignTokens.Spacing.sm)` (line 40)

**Step 6: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift PdfDiffApp/PdfDiff/Views/Compare/SideBySideView.swift PdfDiffApp/PdfDiff/Views/Compare/SwipeView.swift PdfDiffApp/PdfDiff/Views/Compare/OnionSkinView.swift PdfDiffApp/PdfDiff/Views/Compare/DiffOverlayView.swift
git commit -m "refactor: apply DesignTokens to all compare sub-views"
```

---

### Task 14: Apply tokens to inspector sub-views

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectionSidebar.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/SeparationViewer.swift`

**Step 1: InspectionSidebar**

- Replace local `severityColor` function calls with `DesignTokens.issueSeverityColor`
- Replace local `severityIcon` function calls with `DesignTokens.issueSeverityIcon`
- Delete the local `severityColor(_:)` and `severityIcon(_:)` helper functions (lines 154-168)
- Replace `.padding(12)` on header (line 47) with `.padding(DesignTokens.Spacing.md)`
- Replace `.padding(.horizontal, 12)` on issue rows (line 117) with `.padding(.horizontal, DesignTokens.Spacing.md)`
- Replace `.padding(.vertical, 8)` on issue rows (line 118) with `.padding(.vertical, DesignTokens.Spacing.sm)`
- Replace `.padding(12)` on footer (line 149) with `.padding(DesignTokens.Spacing.md)`
- Replace `Color.accentColor.opacity(0.1)` on selected row (line 119) with `Color.accentColor.opacity(0.1)` (keep as-is, it's semantic)
- Replace `.animation(.easeInOut(duration: 0.2))` (line 122) with `.animation(DesignTokens.Motion.snappy)`
- Replace `.font(.headline)` (line 27) with `.font(DesignTokens.Typo.sectionHeader)`

**Step 2: IssuePinView**

- Replace local `severityColor` computed property with `DesignTokens.issueSeverityColor(issue.severity)`
- Replace local `severityIcon` computed property with `DesignTokens.issueSeverityIcon(issue.severity)`
- Delete the local `severityColor` and `severityIcon` computed properties (lines 64-78)
- Replace `.animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false))` (line 19) with `.animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: false))`  (keep as-is, this is intentionally slow for pulsing)
- Replace `.padding(12)` on popover (line 53) with `.padding(DesignTokens.Spacing.md)`
- Replace `.font(.headline)` on popover title (line 41) with `.font(DesignTokens.Typo.sectionHeader)`

**Step 3: SeparationViewer**

- Replace `.font(.headline)` (line 36) with `.font(DesignTokens.Typo.sectionHeader)`
- Replace `.padding(12)` (line 69) with `.padding(DesignTokens.Spacing.md)`
- Replace `VStack(alignment: .leading, spacing: 8)` (line 34) with `VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm)`
- Replace `HStack(spacing: 8)` (line 40) with `HStack(spacing: DesignTokens.Spacing.sm)`
- Replace `.foregroundStyle(.red)` on total ink warning (line 64) with `.foregroundStyle(DesignTokens.Status.fail)`

**Step 4: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/InspectionSidebar.swift PdfDiffApp/PdfDiff/Views/Inspector/IssuePinView.swift PdfDiffApp/PdfDiff/Views/Inspector/SeparationViewer.swift
git commit -m "refactor: apply DesignTokens to inspector sub-views, remove local color helpers"
```

---

### Task 15: Apply tokens to BatchView, SettingsView, PageRendererView

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Batch/BatchView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/SettingsView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Components/PageRendererView.swift`

**Step 1: BatchView**

- Replace `VStack(spacing: 16)` on drop zone (line 20) with `VStack(spacing: DesignTokens.Spacing.lg)`
- Replace `.font(.title3)` on drop text (line 25) with keeping `.font(.title3)` (it's a one-off heading size)
- Replace `.padding(.horizontal, 12)` on toolbar (line 72) with `.padding(.horizontal, DesignTokens.Spacing.md)`
- Replace `.padding(.vertical, 8)` on toolbar (line 73) with `.padding(.vertical, DesignTokens.Spacing.sm)`
- Replace `.font(.headline)` on pairs count (line 50) with `.font(DesignTokens.Typo.sectionHeader)`
- Replace `.font(.caption)` on table cells (lines 78, 79, 83) with `.font(DesignTokens.Typo.toolbarLabel)`
- Replace `.foregroundStyle(.green)` on similarity (line 84) with `.foregroundStyle(DesignTokens.Status.pass)`
- Replace `.foregroundStyle(.orange)` with `.foregroundStyle(DesignTokens.Status.warn)` where `score > 0.9`
- Replace `.foregroundStyle(.red)` with `.foregroundStyle(DesignTokens.Status.fail)` where score is low

**Step 2: SettingsView**

- Replace `.foregroundStyle(.secondary)` (line 34) — keep as-is (it's semantic)
- Replace `.foregroundStyle(.orange)` (line 37) with `.foregroundStyle(DesignTokens.Status.warn)`
- Replace `.foregroundStyle(.green)` (line 40) with `.foregroundStyle(DesignTokens.Status.pass)`
- Replace `.foregroundStyle(.red)` (line 43) with `.foregroundStyle(DesignTokens.Status.fail)`

**Step 3: PageRendererView**

- Replace `.font(.caption)` on label (line 19) with `.font(DesignTokens.Typo.toolbarLabel)`
- Replace `.padding(.vertical, 4)` with `.padding(.vertical, DesignTokens.Spacing.xs)`

**Step 4: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Run all tests**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff 2>&1 | grep -E "(Test Suite|Test Case|Passed|Failed)" | tail -20`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Batch/BatchView.swift PdfDiffApp/PdfDiff/Views/SettingsView.swift PdfDiffApp/PdfDiff/Views/Components/PageRendererView.swift
git commit -m "refactor: apply DesignTokens to BatchView, SettingsView, and PageRendererView"
```

---

## Phase 8: Polish & Keyboard Shortcuts

### Task 16: Add keyboard shortcuts for drawer panels

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`

**Step 1: Add keyboard shortcuts to InspectorView**

Add these modifiers to the outermost `VStack` in InspectorView, after the `.onKeyPress(.escape)`:

```swift
.keyboardShortcut("1", modifiers: .command)  // Won't work directly — use .onKeyPress instead:
```

Actually, since `.keyboardShortcut` requires Buttons, use `.onKeyPress` instead. Add alongside the existing escape handler:

```swift
.onKeyPress("1", modifiers: .command) {
    viewModel.toggleDrawer(.metadata)
    return .handled
}
.onKeyPress("2", modifiers: .command) {
    viewModel.toggleDrawer(.preflight)
    return .handled
}
.onKeyPress("3", modifiers: .command) {
    if viewModel.inspectionResult != nil {
        viewModel.toggleDrawer(.inspection)
        return .handled
    }
    return .ignored
}
```

**Step 2: Add keyboard shortcuts to CompareView**

Add to the outermost `VStack` in CompareView body, alongside escape handler:

```swift
.onKeyPress("1", modifiers: .command) {
    viewModel.toggleDrawer(.diffSummary)
    return .handled
}
.onKeyPress("2", modifiers: .command) {
    viewModel.toggleDrawer(.aiAnalysis)
    return .handled
}
```

**Step 3: Verify build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Inspector/InspectorView.swift PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift
git commit -m "feat: add Cmd+1/2/3 keyboard shortcuts for drawer panels"
```

---

### Task 17: Regenerate Xcode project and final build verification

**Files:**
- Modify: `PdfDiffApp/project.yml` (if needed)
- Regenerate: `PdfDiffApp/PdfDiff.xcodeproj`

**Step 1: Regenerate project**

Run: `cd PdfDiffApp && xcodegen generate`
Expected: Project generated successfully (new files like DesignTokens.swift and GlassDrawer.swift are picked up).

**Step 2: Full build**

Run: `cd PdfDiffApp && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff 2>&1 | grep -E "(Test Suite|Test Case|Passed|Failed)" | tail -20`
Expected: All existing tests pass.

**Step 4: Commit any remaining changes**

```bash
git add -A
git status
# If there are changes:
git commit -m "chore: regenerate Xcode project with new glass UI files"
```

---

## Summary

| Phase | Tasks | Focus |
|-------|-------|-------|
| 1 | 1-2 | Foundation: deployment target + design tokens |
| 2 | 3 | GlassDrawer reusable component |
| 3 | 4 | AppView glass shell |
| 4 | 5-7 | Inspector: drawer state, canvas-first layout, panel tokens |
| 5 | 8-10 | Compare: drawer state, canvas-first layout, DiffSummary tokens |
| 6 | 11 | Glass document slots |
| 7 | 12-15 | Token migration across all remaining views |
| 8 | 16-17 | Keyboard shortcuts + final verification |

**Total: 17 tasks across 8 phases.**
**New files: 2** (DesignTokens.swift, GlassDrawer.swift)
**Modified files: 19** (all existing view files + 2 ViewModels + project.yml)
