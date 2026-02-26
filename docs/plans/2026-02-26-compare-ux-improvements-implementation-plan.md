# Compare View UX Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix broken drop slots, add zoom/pan across all compare modes, add colored diff overlay sub-mode, and implement synchronized side-by-side scrolling.

**Architecture:** Shared `ZoomableContainer` SwiftUI view handles all zoom/pan gestures with optional external bindings for sync. Drop slots expanded to handle both sidebar text drags and Finder file URL drops. Overlay mode gets Blink/Diff sub-mode toggle.

**Tech Stack:** SwiftUI (macOS 14+), Swift 5.10, `MagnifyGesture`, `DragGesture`, `NSEvent` modifier monitoring, `ColorPicker`

---

### Task 1: Fix DocumentSlotView Drop Handling

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`
- Modify: `PdfDiffApp/PdfDiff/ViewModels/AppViewModel.swift`

**Context:** Currently `DocumentSlotView` only accepts `.utf8PlainText` drops (line 70). Sidebar drags use `.draggable(doc.path)` which provides text, but this isn't being picked up reliably. Finder drops provide `.fileURL` which is completely unhandled. The `onDrop` callback signature is `(String) -> Void` taking a path string.

**Step 1: Update DocumentSlotView to accept both file URLs and plain text**

Replace the `.onDrop` handler in `DocumentSlotView.swift` (lines 70-81). The new handler should:
- Accept `[.fileURL, .utf8PlainText]` (file URL first priority)
- For `.fileURL`: use `provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)` to get the URL, validate `.pdf` extension, extract the path string
- For `.utf8PlainText`: keep existing `loadObject(ofClass: String.self)` behavior
- Add `import UniformTypeIdentifiers` at the top

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DocumentSlotView: View {
    let label: String
    let document: OpenedDocument?
    let onDrop: (String) -> Void
    let onClear: () -> Void

    @State private var isTargeted = false
    @State private var dropFailed = false

    // ... body with existing filled/empty slot UI unchanged ...

    // Replace the .onDrop modifier:
    .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isTargeted) { providers in
        handleDrop(providers: providers)
        return true
    }
}
```

Add the drop handler method:

```swift
private func handleDrop(providers: [NSItemProvider]) {
    // Try file URL first (Finder drops)
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else {
                    DispatchQueue.main.async { flashDropFailed() }
                    return
                }
                DispatchQueue.main.async { onDrop(url.path) }
            }
            return
        }
    }
    // Fall back to plain text (sidebar drags)
    for provider in providers {
        _ = provider.loadObject(ofClass: String.self) { path, _ in
            if let path {
                DispatchQueue.main.async { onDrop(path) }
            }
        }
    }
}

private func flashDropFailed() {
    dropFailed = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        dropFailed = false
    }
}
```

Update the empty slot border to show red flash on invalid drop:

```swift
// In the empty slot strokeBorder, change:
isTargeted ? Color.accentColor : Color.secondary.opacity(0.3)
// To:
dropFailed ? Color.red : (isTargeted ? Color.accentColor : Color.secondary.opacity(0.3))
```

**Step 2: Update CompareView onDrop callbacks to handle Finder files**

In `CompareView.swift`, the `onDrop` closures (lines 55-58, 75-78) call `findDocument?(path)` which only finds documents already opened. For Finder drops, we need to open the file first. Change the `findDocument` closure to also accept a URL-based open.

Add an `openAndFind` closure to `CompareView`:

```swift
struct CompareView: View {
    @State var viewModel: CompareViewModel
    var findDocument: ((String) -> OpenedDocument?)? = nil
    var openFileAtPath: ((String) -> OpenedDocument?)? = nil  // NEW: opens file if not found
```

Update both slot onDrop callbacks:

```swift
onDrop: { path in
    if let doc = findDocument?(path) ?? openFileAtPath?(path) {
        viewModel.setLeftDocument(doc)
    }
}
```

Same for right slot.

**Step 3: Wire up openFileAtPath in AppView**

In `AppView.swift` (line 54-57), pass the new closure:

```swift
CompareView(
    viewModel: viewModel.compareViewModel,
    findDocument: { viewModel.document(forPath: $0) },
    openFileAtPath: { path in
        let url = URL(fileURLWithPath: path)
        viewModel.openFiles(urls: [url])
        return viewModel.document(forPath: path)
    }
)
```

**Step 4: Build and test manually**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

Manual test: drag a PDF from Finder into each slot individually. Drag from sidebar into slots. Verify both work.

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift PdfDiffApp/PdfDiff/Views/AppView.swift
git commit -m "fix: drop slots accept both Finder file URLs and sidebar text drags"
```

---

### Task 2: Create ZoomableContainer View

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Components/ZoomableContainer.swift`

**Context:** This is the core reusable zoom/pan view. It wraps any content with `MagnifyGesture` for pinch zoom, `DragGesture` for pan, and supports external bindings for synced mode. It uses `scaleEffect` and `offset` on the content.

**Step 1: Create ZoomableContainer.swift**

```swift
import SwiftUI

struct ZoomableContainer<Content: View>: View {
    let content: Content

    // External bindings (for synced mode) or internal state (standalone)
    @Binding var externalZoom: CGFloat
    @Binding var externalOffset: CGSize
    let useExternalState: Bool

    // Internal state (standalone mode)
    @State private var internalZoom: CGFloat = 1.0
    @State private var internalOffset: CGSize = .zero

    // Gesture tracking
    @State private var lastMagnification: CGFloat = 1.0
    @State private var dragStart: CGSize = .zero

    // Zoom range
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 10.0

    /// Standalone initializer (no external bindings)
    init(@ViewBuilder content: () -> Content) where Content: View {
        self.content = content()
        self._externalZoom = .constant(1.0)
        self._externalOffset = .constant(.zero)
        self.useExternalState = false
    }

    /// Synced initializer (external bindings)
    init(
        zoom: Binding<CGFloat>,
        offset: Binding<CGSize>,
        @ViewBuilder content: () -> Content
    ) where Content: View {
        self.content = content()
        self._externalZoom = zoom
        self._externalOffset = offset
        self.useExternalState = true
    }

    private var currentZoom: CGFloat {
        get { useExternalState ? externalZoom : internalZoom }
    }

    private var currentOffset: CGSize {
        get { useExternalState ? externalOffset : internalOffset }
    }

    private func setZoom(_ value: CGFloat) {
        let clamped = min(maxZoom, max(minZoom, value))
        if useExternalState {
            externalZoom = clamped
        } else {
            internalZoom = clamped
        }
    }

    private func setOffset(_ value: CGSize) {
        if useExternalState {
            externalOffset = value
        } else {
            internalOffset = value
        }
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .scaleEffect(currentZoom, anchor: .center)
                .offset(currentOffset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(magnifyGesture)
                .gesture(panGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if currentZoom > 1.05 {
                            setZoom(1.0)
                            setOffset(.zero)
                        } else {
                            setZoom(2.0)
                        }
                    }
                }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastMagnification
                setZoom(currentZoom * delta)
                lastMagnification = value.magnification
            }
            .onEnded { _ in
                lastMagnification = 1.0
                if currentZoom <= 1.0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        setZoom(1.0)
                        setOffset(.zero)
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard currentZoom > 1.0 else { return }
                setOffset(CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height
                ))
            }
            .onEnded { _ in
                dragStart = currentOffset
            }
    }

    // MARK: - Public zoom actions

    func zoomIn() {
        withAnimation(.easeInOut(duration: 0.15)) {
            setZoom(currentZoom * 1.25)
        }
    }

    func zoomOut() {
        withAnimation(.easeInOut(duration: 0.15)) {
            setZoom(currentZoom / 1.25)
        }
    }

    func fitToWindow() {
        withAnimation(.easeInOut(duration: 0.2)) {
            setZoom(1.0)
            setOffset(.zero)
        }
    }

    func actualSize() {
        withAnimation(.easeInOut(duration: 0.2)) {
            setZoom(1.0) // 1.0 = fit; actual size depends on DPI ratio
            setOffset(.zero)
        }
    }
}
```

Note: The zoom actions (zoomIn, zoomOut, etc.) will be called from the toolbar via the ViewModel rather than directly on this view. We'll wire that in Task 3.

**Step 2: Build to verify**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Components/ZoomableContainer.swift
git commit -m "feat: add ZoomableContainer with pinch zoom, pan, and sync support"
```

---

### Task 3: Add Zoom State to CompareViewModel and Zoom Toolbar

**Files:**
- Modify: `PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`

**Context:** The ViewModel needs to own zoom state so it persists across mode switches and can be shared between side-by-side panels. The toolbar needs zoom controls visible in all modes.

**Step 1: Add zoom state and actions to CompareViewModel**

Add after line 19 (`var structuralDiff: ...`) in `CompareViewModel.swift`:

```swift
// Zoom state (shared across modes, persists on mode switch)
var zoomLevel: CGFloat = 1.0
var panOffset: CGSize = .zero

func zoomIn() {
    withAnimation(.easeInOut(duration: 0.15)) {
        zoomLevel = min(10.0, zoomLevel * 1.25)
    }
}

func zoomOut() {
    withAnimation(.easeInOut(duration: 0.15)) {
        zoomLevel = max(0.1, zoomLevel / 1.25)
    }
}

func zoomFit() {
    withAnimation(.easeInOut(duration: 0.2)) {
        zoomLevel = 1.0
        panOffset = .zero
    }
}

func zoomActualSize() {
    withAnimation(.easeInOut(duration: 0.2)) {
        zoomLevel = 1.0
        panOffset = .zero
    }
}
```

Also reset zoom on page change. In `nextPage()` and `previousPage()`, after updating `currentPage`, add:

```swift
zoomLevel = 1.0
panOffset = .zero
```

And in `renderAndDiff()` reset zoom at the start:

```swift
zoomLevel = 1.0
panOffset = .zero
```

**Step 2: Add zoom toolbar to CompareView**

In `CompareView.swift`, add a zoom toolbar section inside `compareToolbar` between the Sensitivity slider and the page navigation divider:

```swift
Divider().frame(height: 20)

// Zoom controls
HStack(spacing: 4) {
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
        .font(.caption)
        .buttonStyle(.borderless)
}
```

Add keyboard shortcuts to the compare content area (on the `compareContent` view):

```swift
compareContent
    .frame(minHeight: 300)
    .keyboardShortcut("0", modifiers: .command) // Can't use .keyboardShortcut on non-buttons
```

Instead, add `.onKeyPress` or use `Commands` in the app. For now just the toolbar buttons — keyboard shortcuts can be wired in Task 7 (polish).

**Step 3: Build and verify**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift
git commit -m "feat: add zoom state to CompareViewModel and zoom toolbar controls"
```

---

### Task 4: Integrate ZoomableContainer into All View Modes

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/SideBySideView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/SwipeView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/OnionSkinView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`

**Context:** Each view mode needs to wrap its image content in `ZoomableContainer` using the ViewModel's shared zoom bindings. Side-by-side is handled separately in Task 6.

**Step 1: Update AnimatedOverlayView**

Add zoom binding parameters and wrap the ZStack canvas:

```swift
struct AnimatedOverlayView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    // ... existing @State vars ...

    var body: some View {
        VStack(spacing: 0) {
            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            blinkControls
        }
        // ... existing onAppear/onDisappear/onChange ...
    }
```

**Step 2: Update SwipeView**

Add zoom bindings and wrap the entire GeometryReader content. The swipe divider drag needs `.highPriorityGesture`:

```swift
struct SwipeView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    @State private var dividerPosition: CGFloat = 0.5

    var body: some View {
        ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
            GeometryReader { geometry in
                let dividerX = geometry.size.width * dividerPosition
                ZStack {
                    // ... existing right image, left image clipped, divider line ...

                    // Drag handle — use .highPriorityGesture so it overrides pan
                    Circle()
                        // ... existing styling ...
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { value in
                                    dividerPosition = max(0.05, min(0.95, value.location.x / geometry.size.width))
                                }
                        )

                    // ... existing labels ...
                }
            }
        }
    }
}
```

**Step 3: Update OnionSkinView**

```swift
struct OnionSkinView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    @State private var opacity: Double = 0.5

    var body: some View {
        VStack(spacing: 0) {
            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
                ZStack {
                    if let leftImage {
                        Image(nsImage: leftImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    if let rightImage {
                        Image(nsImage: rightImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            // ... existing opacity controls unchanged ...
        }
    }
}
```

**Step 4: Update CompareView to pass zoom bindings**

In `CompareView.swift` `compareContent`, pass the bindings:

```swift
@ViewBuilder
private var compareContent: some View {
    switch viewModel.compareMode {
    case .overlay:
        AnimatedOverlayView(
            leftImage: viewModel.leftImage,
            rightImage: viewModel.rightImage,
            zoomLevel: $viewModel.zoomLevel,
            panOffset: $viewModel.panOffset
        )
    case .sideBySide:
        SideBySideView(
            leftImage: viewModel.leftImage,
            rightImage: viewModel.rightImage,
            leftLabel: viewModel.leftDocument?.fileName,
            rightLabel: viewModel.rightDocument?.fileName,
            zoomLevel: $viewModel.zoomLevel,
            panOffset: $viewModel.panOffset
        )
    case .swipe:
        SwipeView(
            leftImage: viewModel.leftImage,
            rightImage: viewModel.rightImage,
            zoomLevel: $viewModel.zoomLevel,
            panOffset: $viewModel.panOffset
        )
    case .onionSkin:
        OnionSkinView(
            leftImage: viewModel.leftImage,
            rightImage: viewModel.rightImage,
            zoomLevel: $viewModel.zoomLevel,
            panOffset: $viewModel.panOffset
        )
    }
}
```

**Step 5: Update SideBySideView signature (full sync in Task 6)**

For now, SideBySideView wraps both panels in a single ZoomableContainer:

```swift
struct SideBySideView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    let leftLabel: String?
    let rightLabel: String?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    var body: some View {
        ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
            HStack(spacing: 1) {
                imagePanel(image: leftImage, label: leftLabel)
                Divider()
                imagePanel(image: rightImage, label: rightLabel)
            }
        }
    }

    private func imagePanel(image: NSImage?, label: String?) -> some View {
        VStack(spacing: 0) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("No page")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
```

Note: This replaces `PageRendererView` usage in SideBySideView since `ZoomableContainer` now handles the scrolling. `PageRendererView` is still used in `InspectorView` so don't delete it.

**Step 6: Build and verify**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift PdfDiffApp/PdfDiff/Views/Compare/SideBySideView.swift PdfDiffApp/PdfDiff/Views/Compare/SwipeView.swift PdfDiffApp/PdfDiff/Views/Compare/OnionSkinView.swift PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift
git commit -m "feat: integrate ZoomableContainer into all compare view modes"
```

---

### Task 5: Add Colored Diff Overlay Sub-mode

**Files:**
- Create: `PdfDiffApp/PdfDiff/Views/Compare/DiffOverlayView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`
- Modify: `PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift`

**Context:** The overlay mode needs a Blink/Diff segmented toggle. Blink is the existing `AnimatedOverlayView`. Diff is a new view that shows the left image with changed pixels highlighted in a user-chosen color. The diff image already comes from `computePixelDiff()` as `diffResult.diffImage`.

**Step 1: Add overlay sub-mode enum to CompareViewModel**

In `CompareViewModel.swift`, add inside the class:

```swift
enum OverlaySubMode: String, CaseIterable {
    case blink = "Blink"
    case diff = "Diff"
}

var overlaySubMode: OverlaySubMode = .blink
var diffOverlayColor: Color = .red
var diffOverlayOpacity: Double = 0.5
```

**Step 2: Create DiffOverlayView**

```swift
import SwiftUI

struct DiffOverlayView: View {
    let leftImage: NSImage?
    let diffImage: NSImage?
    @Binding var overlayColor: Color
    @Binding var overlayOpacity: Double
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    var body: some View {
        VStack(spacing: 0) {
            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset) {
                ZStack {
                    if let leftImage {
                        Image(nsImage: leftImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }

                    if let diffImage {
                        Image(nsImage: diffImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .colorMultiply(overlayColor)
                            .opacity(overlayOpacity)
                            .blendMode(.multiply)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Diff overlay controls
            HStack(spacing: 16) {
                ColorPicker("Highlight", selection: $overlayColor, supportsOpacity: false)
                    .frame(width: 120)

                HStack(spacing: 8) {
                    Text("Opacity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $overlayOpacity, in: 0.1...1.0)
                        .frame(width: 100)
                    Text(String(format: "%.0f%%", overlayOpacity * 100))
                        .font(.caption.monospacedDigit())
                        .frame(width: 36)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
```

**Step 3: Add sub-mode picker to AnimatedOverlayView and CompareView**

The sub-mode picker should appear within the overlay mode's content area. Update `CompareView.swift` to switch between blink and diff sub-modes when in overlay mode:

```swift
case .overlay:
    VStack(spacing: 0) {
        // Sub-mode picker
        Picker("", selection: $viewModel.overlaySubMode) {
            ForEach(CompareViewModel.OverlaySubMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .padding(.vertical, 6)

        switch viewModel.overlaySubMode {
        case .blink:
            AnimatedOverlayView(
                leftImage: viewModel.leftImage,
                rightImage: viewModel.rightImage,
                zoomLevel: $viewModel.zoomLevel,
                panOffset: $viewModel.panOffset
            )
        case .diff:
            DiffOverlayView(
                leftImage: viewModel.leftImage,
                diffImage: viewModel.diffResult?.diffImage,
                overlayColor: $viewModel.diffOverlayColor,
                overlayOpacity: $viewModel.diffOverlayOpacity,
                zoomLevel: $viewModel.zoomLevel,
                panOffset: $viewModel.panOffset
            )
        }
    }
```

**Step 4: Build and verify**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/DiffOverlayView.swift PdfDiffApp/PdfDiff/Views/Compare/AnimatedOverlayView.swift PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift PdfDiffApp/PdfDiff/ViewModels/CompareViewModel.swift
git commit -m "feat: add colored diff overlay sub-mode with adjustable color and opacity"
```

---

### Task 6: Implement Synced Scrolling for Side-by-Side with Option-Key Decouple

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/SideBySideView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Components/ZoomableContainer.swift`

**Context:** Side-by-side needs two separate `ZoomableContainer`s sharing the same zoom/pan state. Holding Option temporarily decouples them. On release, the decoupled panel snaps back to shared state.

**Step 1: Add isIndependent support to ZoomableContainer**

Add an `isIndependent` parameter that, when true, makes the container use internal state and ignore external bindings:

```swift
struct ZoomableContainer<Content: View>: View {
    // ... existing properties ...
    var isIndependent: Bool = false

    // When independent, use internal state that starts from external
    @State private var independentZoom: CGFloat = 1.0
    @State private var independentOffset: CGSize = .zero

    private var activeZoom: CGFloat {
        if isIndependent { return independentZoom }
        return useExternalState ? externalZoom : internalZoom
    }

    private var activeOffset: CGSize {
        if isIndependent { return independentOffset }
        return useExternalState ? externalOffset : internalOffset
    }
    // ... update setZoom/setOffset to use active state ...
```

Also add `.onChange(of: isIndependent)` to snapshot the current shared state when entering independent mode, and animate back when leaving:

```swift
.onChange(of: isIndependent) { wasIndependent, nowIndependent in
    if nowIndependent {
        // Entering independent mode: snapshot current shared state
        independentZoom = useExternalState ? externalZoom : internalZoom
        independentOffset = useExternalState ? externalOffset : internalOffset
    } else {
        // Leaving independent mode: snap back to shared
        withAnimation(.easeOut(duration: 0.2)) {
            // No action needed: view will read from shared state again
        }
    }
}
```

**Step 2: Update SideBySideView with Option-key monitoring and independent panels**

Replace the single-container approach from Task 4 with two separate containers:

```swift
struct SideBySideView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    let leftLabel: String?
    let rightLabel: String?
    @Binding var zoomLevel: CGFloat
    @Binding var panOffset: CGSize

    @State private var optionHeld = false
    @State private var hoveredPanel: Panel? = nil

    enum Panel { case left, right }

    var body: some View {
        HStack(spacing: 1) {
            panelView(image: leftImage, label: leftLabel, panel: .left)
            Divider()
            panelView(image: rightImage, label: rightLabel, panel: .right)
        }
        .onAppear { installModifierMonitor() }
        .onDisappear { removeModifierMonitor() }
    }

    private func panelView(image: NSImage?, label: String?, panel: Panel) -> some View {
        let isIndependent = optionHeld && hoveredPanel == panel

        return VStack(spacing: 0) {
            if let label {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isIndependent {
                        Image(systemName: "lock.open.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            ZoomableContainer(zoom: $zoomLevel, offset: $panOffset, isIndependent: isIndependent) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text("No page")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onHover { hovering in
                hoveredPanel = hovering ? panel : nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Modifier key monitoring

    @State private var monitor: Any? = nil

    private func installModifierMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            optionHeld = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func removeModifierMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
```

Note: `ZoomableContainer` initializer with `isIndependent` parameter will need a third init variant. Add to ZoomableContainer:

```swift
/// Synced initializer with independence toggle
init(
    zoom: Binding<CGFloat>,
    offset: Binding<CGSize>,
    isIndependent: Bool = false,
    @ViewBuilder content: () -> Content
) where Content: View {
    self.content = content()
    self._externalZoom = zoom
    self._externalOffset = offset
    self.useExternalState = true
    self.isIndependent = isIndependent
}
```

**Step 3: Build and verify**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/SideBySideView.swift PdfDiffApp/PdfDiff/Views/Components/ZoomableContainer.swift
git commit -m "feat: synced side-by-side scrolling with Option-key decouple"
```

---

### Task 7: UI/UX Polish — Drop Feedback, Cursor, Keyboard Shortcuts

**Files:**
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift`
- Modify: `PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift`
- Modify: `PdfDiffApp/PdfDiff/PdfDiffApp.swift`

**Context:** Polish pass: improved drop slot animations, keyboard shortcuts for zoom, and minor visual refinements.

**Step 1: Enhance drop slot visual feedback**

In `DocumentSlotView.swift`, add a scale animation on valid hover and a success flash:

```swift
@State private var dropSucceeded = false

// On the empty slot VStack, add:
.scaleEffect(isTargeted ? 1.02 : 1.0)
.animation(.easeInOut(duration: 0.15), value: isTargeted)
```

After a successful drop, briefly show a checkmark. In the `handleDrop` method, when `onDrop` is called, set `dropSucceeded = true` briefly:

```swift
DispatchQueue.main.async {
    onDrop(url.path)
    dropSucceeded = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        dropSucceeded = false
    }
}
```

Add a checkmark overlay on the empty slot when `dropSucceeded`:

```swift
.overlay {
    if dropSucceeded {
        Image(systemName: "checkmark.circle.fill")
            .font(.title)
            .foregroundStyle(.green)
            .transition(.scale.combined(with: .opacity))
    }
}
.animation(.easeInOut(duration: 0.2), value: dropSucceeded)
```

**Step 2: Add keyboard shortcuts for zoom**

In `PdfDiffApp.swift` (the `@main` App struct), add commands:

```swift
@main
struct PdfDiffApp: App {
    // ... existing body ...

    var body: some Scene {
        WindowGroup {
            // ... existing content ...
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { NotificationCenter.default.post(name: .zoomIn, object: nil) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { NotificationCenter.default.post(name: .zoomOut, object: nil) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Fit to Window") { NotificationCenter.default.post(name: .zoomFit, object: nil) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}

extension Notification.Name {
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomFit = Notification.Name("zoomFit")
}
```

In `CompareView.swift`, listen for these notifications:

```swift
.onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
    viewModel.zoomIn()
}
.onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
    viewModel.zoomOut()
}
.onReceive(NotificationCenter.default.publisher(for: .zoomFit)) { _ in
    viewModel.zoomFit()
}
```

**Step 3: Build and verify**

Run: `cd PdfDiffApp && xcodegen generate && xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiff/Views/Compare/DocumentSlotView.swift PdfDiffApp/PdfDiff/Views/Compare/CompareView.swift PdfDiffApp/PdfDiff/PdfDiffApp.swift
git commit -m "feat: drop slot animations, zoom keyboard shortcuts, UI polish"
```

---

### Task 8: Update Tests

**Files:**
- Modify: `PdfDiffApp/PdfDiffTests/ViewModels/CompareViewModelTests.swift`

**Context:** Add tests for the new zoom state, overlay sub-mode, and diff overlay properties.

**Step 1: Write tests for zoom state**

```swift
@Test("zoom resets on page change")
func zoomResetsOnPageChange() async {
    let left = try! mockService.openDocument(path: "/left.pdf")
    let right = try! mockService.openDocument(path: "/right.pdf")
    let vm = CompareViewModel(pdfService: mockService)

    await vm.setDocuments(left: left, right: right)
    vm.zoomLevel = 2.5
    vm.panOffset = CGSize(width: 100, height: 50)

    vm.nextPage()

    #expect(vm.zoomLevel == 1.0)
    #expect(vm.panOffset == .zero)
}

@Test("zoom in increases zoom level")
func zoomInIncreasesLevel() async {
    let vm = CompareViewModel(pdfService: mockService)
    let initial = vm.zoomLevel
    vm.zoomIn()
    #expect(vm.zoomLevel > initial)
}

@Test("zoom out decreases zoom level")
func zoomOutDecreasesLevel() async {
    let vm = CompareViewModel(pdfService: mockService)
    vm.zoomLevel = 2.0
    vm.zoomOut()
    #expect(vm.zoomLevel < 2.0)
}

@Test("zoom fit resets to 1.0")
func zoomFitResetsLevel() async {
    let vm = CompareViewModel(pdfService: mockService)
    vm.zoomLevel = 3.0
    vm.panOffset = CGSize(width: 50, height: 50)
    vm.zoomFit()
    #expect(vm.zoomLevel == 1.0)
    #expect(vm.panOffset == .zero)
}
```

**Step 2: Write tests for overlay sub-mode defaults**

```swift
@Test("default overlay sub-mode is blink")
func defaultOverlaySubMode() async {
    let vm = CompareViewModel(pdfService: mockService)
    #expect(vm.overlaySubMode == .blink)
}

@Test("diff overlay color defaults to red")
func defaultDiffOverlayColor() async {
    let vm = CompareViewModel(pdfService: mockService)
    #expect(vm.diffOverlayColor == .red)
}

@Test("diff overlay opacity defaults to 0.5")
func defaultDiffOverlayOpacity() async {
    let vm = CompareViewModel(pdfService: mockService)
    #expect(vm.diffOverlayOpacity == 0.5)
}
```

**Step 3: Run tests**

Run: `cd PdfDiffApp && xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | grep -E '(Test Suite|Test Case|passed|failed|error:)'`
Expected: All tests pass (existing 9 + new 7 = 16 tests)

**Step 4: Commit**

```bash
git add PdfDiffApp/PdfDiffTests/ViewModels/CompareViewModelTests.swift
git commit -m "test: add zoom state and overlay sub-mode tests"
```

---

### Task 9: Final Integration Verification

**Files:** None (verification only)

**Step 1: Regenerate Xcode project**

Run: `cd PdfDiffApp && xcodegen generate`

**Step 2: Full build**

Run: `xcodebuild -project PdfDiff.xcodeproj -scheme PdfDiff build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run: `xcodebuild test -project PdfDiff.xcodeproj -scheme PdfDiff -destination 'platform=macOS' 2>&1 | grep -E '(Test Suite|Test Case|passed|failed|error:)'`
Expected: All 16 tests pass

**Step 4: Manual smoke test checklist**

1. Drop a PDF from Finder into left slot → should accept and show document
2. Drop a PDF from Finder into right slot → should accept and show document
3. Drop a PDF from sidebar into a slot → should accept
4. Both slots filled → compare view appears
5. Pinch-to-zoom on trackpad → image zooms, toolbar shows percentage
6. Click + and - buttons → zoom changes
7. Click "Fit" → returns to 100%
8. Double-click image → toggles between fit and 2x
9. Switch to Side-by-Side → zoom preserved
10. Zoom in side-by-side → both panels zoom together
11. Hold Option + pan one panel → it moves independently, shows lock icon
12. Release Option → panel snaps back to shared position
13. Switch to Overlay mode → see Blink/Diff toggle
14. Select Diff sub-mode → shows red-highlighted differences
15. Change color picker → overlay color changes
16. Adjust opacity slider → overlay opacity changes
17. Switch to Swipe mode → zoom works, divider still draggable
18. Switch to Onion Skin → zoom works, opacity slider still works
19. Navigate to next page → zoom resets to fit
20. Cmd+= → zoom in, Cmd+- → zoom out, Cmd+0 → fit
