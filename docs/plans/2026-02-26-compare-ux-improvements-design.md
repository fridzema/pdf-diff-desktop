# Compare View UX Improvements Design

**Date:** 2026-02-26
**Status:** Approved

## Summary

Fix broken drop slots, add zoom controls across all view modes, add colored diff overlay sub-mode, and implement synchronized scrolling for side-by-side view.

## 1. Fix Drop Slots

**Problem:** `DocumentSlotView` only handles `.utf8PlainText` drops. Sidebar drags provide text paths, Finder drags provide file URLs. Both are currently failing.

**Design:**

- Expand `DocumentSlotView.onDrop` to accept both `.utf8PlainText` (sidebar) and `.fileURL` (Finder)
- For `.fileURL` drops: extract the URL, validate it's a PDF, pass the path string up
- For `.utf8PlainText` drops: keep existing behavior (path string from sidebar)
- When a file is dropped from Finder that isn't already in the document list, call `AppViewModel.openFiles(urls:)` first to register it, then assign to the slot
- Visual feedback: slot border pulses accent color on valid hover, turns red briefly on invalid file type

**Drop callback chain:**
```
DocumentSlotView receives drop
  → tries .fileURL first, falls back to .utf8PlainText
  → validates PDF extension
  → calls onDrop(path) to parent
  → CompareView resolves document (opens if needed)
  → assigns to left/right slot
```

## 2. ZoomableContainer

A reusable SwiftUI view wrapping any image content with zoom and pan.

**State:**
- `zoomLevel: CGFloat` — range 0.1x to 10x, default 1.0 (fit-to-window)
- `panOffset: CGSize` — translation from center
- `isPanning: Bool` — tracking drag state

**Gestures:**
- **MagnifyGesture** (trackpad pinch): multiplies zoom level, anchored to gesture location
- **Scroll wheel + Cmd**: zoom in/out in discrete steps
- **DragGesture**: pan when zoomed in (only active when zoom > fit level)
- Pan resets when zooming back to fit

**External bindings:**
- Accepts optional `Binding<CGFloat>` for zoom and `Binding<CGSize>` for pan offset
- Enables side-by-side sync: both containers bind to the same state
- When no binding provided, uses internal `@State` (standalone mode)

**Zoom toolbar** (in the compare toolbar area):
- `-` button, zoom percentage label (clickable → fit), `+` button, `100%` button
- Keyboard: Cmd+0 = fit-to-window, Cmd+1 = 100%, Cmd+= zoom in, Cmd+- zoom out

**Integration per view mode:**
- **Overlay (blink):** single ZoomableContainer, zoom persists across blink toggle
- **Overlay (diff):** single ZoomableContainer wrapping the colored diff image
- **Side-by-side:** two ZoomableContainers sharing one zoom/pan binding (smart sync)
- **Swipe:** single ZoomableContainer, swipe drag gets `.highPriorityGesture` over pan
- **Onion skin:** single ZoomableContainer wrapping the blended ZStack

## 3. Colored Diff Overlay Sub-mode

Add a sub-mode toggle within Overlay mode: **Blink** (existing) and **Diff** (new).

**Diff sub-mode behavior:**
- Shows the left (reference) document as the base image
- Pixels that differ are highlighted with a colored overlay
- Default color: red with adjustable opacity (50% default)
- Color picker: SwiftUI `ColorPicker` in the overlay controls bar
- Unchanged pixels show through at full clarity

**Implementation:**
- Reuse existing `computePixelDiff()` from Rust core which produces a diff bitmap
- Use the diff bitmap as a mask, tinted with chosen color at chosen opacity
- Composite in SwiftUI: base image (left) + diff mask tinted with color
- No new Rust work required

**UI layout for Overlay mode:**
```
[Blink | Diff]  ← segmented picker (sub-mode toggle)

If Blink: existing AnimatedOverlayView controls (play/pause, speed, manual toggle)
If Diff:  [Color picker: red] [Opacity slider: 50%]
```

The sub-mode picker sits inside the overlay view's control bar, not the main toolbar.

## 4. Synced Scrolling & Zoom for Side-by-Side

**Default behavior (synced):**
- Both panels share the same `zoomLevel` and `panOffset` bindings
- Scrolling/zooming either panel moves both simultaneously
- Shared binding lives in `CompareViewModel` for persistence across page changes

**Option-key decouple:**
- While holding Option, gestures only affect the panel under the cursor
- Each panel gets a temporary independent delta while Option is held
- On Option release, the panel snaps back to the shared position (0.2s animation)
- Visual indicator: small "unlocked" icon in corner of independently scrolled panel

**Technical approach:**
- `ZoomableContainer` accepts `isIndependent: Bool` flag
- Track modifier keys via `.onModifierKeysChanged` (macOS 14+) or `NSEvent.addLocalMonitorForEvents`
- When Option detected, active panel switches to internal state
- On release, animated lerp back to shared state

## 5. Zoom in Remaining View Modes

**Swipe mode:**
- Single ZoomableContainer wraps entire ZStack (both images + divider)
- Swipe divider drag gets `.highPriorityGesture` over pan
- Pan only activates when dragging outside the divider handle area

**Onion skin mode:**
- Single ZoomableContainer wraps blended ZStack
- Opacity slider unaffected by zoom
- Both layers zoom together

**Animated overlay (blink):**
- Single ZoomableContainer, zoom persists across left/right blink toggle

**Diff overlay:**
- Single ZoomableContainer wrapping base image + colored diff mask

**Zoom toolbar placement:**
- In main compare toolbar, visible in all modes
- Shows: `[ - ]  125%  [ + ]  [ Fit ]  [ 1:1 ]`
- Zoom resets to fit on page change, persists on mode switch

## 6. UI/UX Polish

**Drop slot feedback:**
- Valid PDF hover: dashed border animates to solid accent color, slight scale-up (1.02x)
- Invalid file type: border flashes red briefly
- Successful drop: brief checkmark animation

**Zoom UX:**
- Zoom anchors to cursor position (not center)
- Double-click toggles between fit-to-window and 100%
- Zoom percentage clickable → popover with presets (25%, 50%, 100%, 200%, 400%)

**Cursor feedback:**
- Zoomed in: open hand (pan ready), closed hand while dragging
- Over swipe divider: horizontal resize cursor

**State persistence:**
- Zoom level and pan persist across mode switches (stored in ViewModel)
- Reset on page change or new document load

**Keyboard shortcuts:**
- Cmd+0: fit to window
- Cmd+1: actual size (100%)
- Cmd+=: zoom in
- Cmd+-: zoom out
