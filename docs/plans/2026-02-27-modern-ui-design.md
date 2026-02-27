# Modern UI Design: Liquid Glass Refresh

## Overview

Comprehensive UI modernization of PDF Diff Desktop using macOS Tahoe's Liquid Glass design language. Targets three problems: utilitarian appearance, panel density/clutter, and inconsistent styling across views.

**Target:** macOS 26 (Tahoe) only — uses native Liquid Glass APIs directly.
**Approach:** Glass Navigation Shell + Floating Panels (canvas-first with on-demand overlay drawers).
**Scope:** All 21 view files touched. No structural changes to navigation (Inspector/Compare/Batch tabs stay). No functional changes — purely visual and layout.

## 1. Design Token System

Replace scattered hardcoded values with a centralized `DesignTokens` enum. All views reference tokens instead of raw numbers.

```swift
enum DesignTokens {
    enum Spacing {
        static let xs: CGFloat = 4    // tight internal
        static let sm: CGFloat = 8    // between related elements
        static let md: CGFloat = 12   // standard padding
        static let lg: CGFloat = 16   // between sections
        static let xl: CGFloat = 24   // major section gaps
        static let xxl: CGFloat = 32  // breathing room
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let pill: CGFloat = .infinity
    }

    enum Status {
        static let pass = Color.green
        static let warn = Color.orange
        static let fail = Color.red
        static let info = Color.blue
    }

    enum Type {
        static let toolbarLabel = Font.caption
        static let sectionHeader = Font.headline
        static let bodyMono = Font.body.monospacedDigit()
        static let metric = Font.system(.title3, design: .rounded).monospacedDigit()
    }

    enum Motion {
        static let snappy = Animation.snappy(duration: 0.25)
        static let smooth = Animation.smooth(duration: 0.35)
        static let bouncy = Animation.bouncy(duration: 0.4)
    }
}
```

**Rationale:**
- 8pt grid for spacing (industry standard, aligns with Apple HIG).
- Semantic color names (`pass/warn/fail/info`) replace raw `.green`/`.red` references.
- Named animation curves replace scattered `.easeInOut(duration: 0.3)`.
- Rounded monospaced digits for metrics — more polished than raw monospaced.

## 2. Glass Navigation Shell

### 2.1 Tab Picker

The top-level `Picker` (Inspector / Compare / Batch) is wrapped in a `GlassEffectContainer` along with adjacent toolbar items. On Tahoe, the segmented control automatically gets glass styling. The container ensures they share a sampling region and can morph together.

```
┌──────────────────────────────────────────────────┐
│ ░░░ GlassEffectContainer ░░░░░░░░░░░░░░░░░░░░░░ │
│   [ Inspector | Compare | Batch ]    ⚙ Settings  │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
└──────────────────────────────────────────────────┘
```

### 2.2 Mode Toolbars

Each mode's toolbar uses `ToolbarSpacer` to create logical groups. Related controls cluster together with glass flowing between them.

**Inspector toolbar:**
```
[◀ Page ▶] ····· [- Zoom % +] ····· [🔍 Inspect] [📋 Report] | [📊] [✅] [ℹ️]
                                                                  ^drawer toggles
```

**Compare toolbar:**
```
[Overlay|Side|Swipe|Onion] ····· [Sensitivity ▼] ····· [- Zoom +] ····· [🤖 AI] | [📊]
                                                                                    ^drawer
```

`·····` = `ToolbarSpacer()` (flexible). `|` = `ToolbarSpacer(fixed: 8)`.

### 2.3 Sidebar

The `NavigationSplitView` sidebar gets automatic glass treatment on Tahoe. Additional changes:
- Minimum row height increased to 44pt for better click targets.
- Selected row uses glass-tinted accent background.
- Hover state: gentle glass highlight with `glassEffect(.regular.tint(.accentColor.opacity(0.3)))`.

## 3. Panel System Redesign

### 3.1 Problem

Current `VSplitView` stacks 2-3 panels vertically below the canvas, each claiming 150-300pt. The canvas gets squeezed to ~40-50% of available height.

### 3.2 Solution: Canvas-First with Overlay Drawers

```
┌─────────────────────────────────┐
│ Toolbar            [📋] [🔍] [ℹ] │  ← toggle buttons for panels
├─────────────────────────────────┤
│                                 │
│                                 │
│ Canvas (FULL HEIGHT)            │  ← gets all available space
│                                 │
│                                 │
│    ┌────────────────────────┐   │
│    │ ░░ Glass Drawer ░░░░░░ │   │  ← slides up from bottom
│    │ Panel content here     │   │     overlays canvas
│    │ ...                    │   │     max 40% of view height
│    └────────────────────────┘   │
└─────────────────────────────────┘
```

### 3.3 Drawer Behavior

- **Triggers:** Toolbar toggle buttons for each panel type. SF Symbols with `.badge` when results are available.
- **Overlay:** Drawer slides up from the bottom of the canvas. It overlays the canvas (does not push it). Maximum 40% of view height.
- **Glass backdrop:** `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))`.
- **One at a time:** Opening a second drawer replaces the first with a morphing animation (`glassEffectID` in a shared `GlassEffectContainer`).
- **Dismiss:** Click toggle again, press Escape, or click outside.
- **Keyboard shortcuts:**
  - Inspector: `Cmd+1` Metadata, `Cmd+2` Preflight, `Cmd+3` AI Results
  - Compare: `Cmd+1` Diff Summary, `Cmd+2` AI Analysis

### 3.4 Inspector Specifics

- Inspection sidebar (AI issue list) becomes a right-side glass overlay, toggled from toolbar.
- Issue pins on canvas remain unchanged.
- Separation viewer stays inline (it replaces the canvas content, not a panel).

### 3.5 Compare Specifics

- Document slot area stays fixed at top.
- Compare mode content gets full remaining height.
- Diff Summary becomes a bottom overlay drawer.

## 4. Document Slots & Drop Zones

Compare view's document slots get a glass refresh within a `GlassEffectContainer`:

```
┌─────────────────────────────────────────────┐
│  ░░░░░░░░░░ GlassEffectContainer ░░░░░░░░░ │
│  ┌─ Glass Card ──┐  ⇄  ┌─ Glass Card ──┐  │
│  │ 📄 design.pdf │     │ 📄 proof.pdf  │  │
│  │ 3 pages       │     │ 3 pages       │  │
│  └───────────────┘     └───────────────┘  │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
└─────────────────────────────────────────────┘
```

- **Empty slots:** `.glassEffect(.clear)` with "Drop PDF here" label and down-arrow icon.
- **Filled slots:** `.glassEffect(.regular.tint(.accentColor))` with document name + page count.
- **Swap button:** Glass-backed circular button between slots.
- **Drop hover:** Glass tint shifts to accent color with `.bouncy` animation.
- **Success:** Brief green tint flash. **Failure:** Brief red tint flash.

## 5. Micro-Interactions & Polish

### 5.1 Drawer Transitions
- Slides up with `Animation.snappy(duration: 0.25)`.
- Glass morphing when switching drawers (e.g., Metadata to Preflight) via `glassEffectID`.
- Content fades in 50ms after drawer reaches position (prevents content jumping during slide).

### 5.2 Toolbar Button Feedback
- Active panel toggle: `.tint(.accentColor)` on glass effect.
- Inactive toggles: neutral `.regular` glass.

### 5.3 Canvas Background
- Dark mode: near-black `Color(white: 0.08)`.
- Light mode: warm off-white `Color(white: 0.96)`.

### 5.4 Severity Badges
- Keep existing green/orange/red/blue semantic colors.
- Apply `.glassEffect(.regular.tint(status.color))` to each badge.

## 6. Files Affected

All changes are in `PdfDiffApp/PdfDiff/`:

| File | Change Type |
|------|-------------|
| `DesignTokens.swift` (NEW) | Centralized spacing, colors, typography, animation tokens |
| `GlassDrawer.swift` (NEW) | Reusable overlay drawer component with glass backdrop |
| `Views/AppView.swift` | Glass tab picker, GlassEffectContainer, toolbar grouping |
| `Views/Inspector/InspectorView.swift` | Remove VSplitView, add drawer toggles, full-height canvas |
| `Views/Inspector/MetadataPanel.swift` | Adapt to drawer container, use design tokens |
| `Views/Inspector/PreflightPanel.swift` | Adapt to drawer container, use design tokens |
| `Views/Inspector/InspectionSidebar.swift` | Glass overlay from right side, use tokens |
| `Views/Inspector/IssuePinView.swift` | Glass-backed badges, use tokens |
| `Views/Inspector/SeparationViewer.swift` | Use design tokens for spacing/colors |
| `Views/Compare/CompareView.swift` | Remove VSplitView, add drawer toggle, full-height canvas |
| `Views/Compare/DocumentSlotView.swift` | Glass cards, GlassEffectContainer, tinted drop feedback |
| `Views/Compare/DiffSummaryPanel.swift` | Adapt to drawer, glass badges, use tokens |
| `Views/Compare/AnimatedOverlayView.swift` | Use design tokens |
| `Views/Compare/SideBySideView.swift` | Use design tokens |
| `Views/Compare/DiffOverlayView.swift` | Use design tokens |
| `Views/Compare/SwipeView.swift` | Glass swipe handle, use tokens |
| `Views/Compare/OnionSkinView.swift` | Use design tokens |
| `Views/Batch/BatchView.swift` | Glass table styling, use tokens |
| `Views/Components/ZoomToolbar.swift` | Glass button group, use tokens |
| `Views/Components/ZoomableContainer.swift` | Canvas background, use tokens |
| `Views/Components/PageRendererView.swift` | Use design tokens |
| `Views/SettingsView.swift` | Glass form styling, use tokens |

## 7. Non-Goals

- No navigation restructure (tabs stay as-is).
- No functional changes (same features, same data flow).
- No backward compatibility with pre-Tahoe macOS.
- No detachable floating palette windows (can add later).
- No new ViewModels or data model changes.

## 8. References

- [Build a SwiftUI app with the new design — WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Applying Liquid Glass to custom views — Apple Docs](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [GlassEffectContainer — Apple Docs](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Liquid Glass Reference (community)](https://github.com/conorluddy/LiquidGlassReference)
