# PDF Diff Desktop — UX Redesign for Prepress/QC Workflow

**Date:** 2026-02-26
**Goal:** Make the app usable for DTP operators and QC professionals by wiring up all compare features behind a clear, document-first navigation model with easy compare entry.

**Reference:** Kaleidoscope (document-first, comparison-focused UX)

---

## Design Decisions

- **Document-first with easy compare entry** — open PDFs, browse in sidebar, select two to compare
- **Tab-based mode switching** — detail area toggles between Inspector and Compare via segmented control
- **Overlay with animated blink as default** — classic prepress proofing technique, auto-toggles left/right
- **All compare modes available** — Overlay, Side-by-Side, Swipe, Onion Skin, switchable via toolbar picker
- **Compare replaces detail area** — no separate window, sidebar stays visible for drag targets
- **No new Rust code** — all changes are SwiftUI views and view models

---

## Window Layout

```
┌──────────────────────────────────────────────────────────────┐
│  PDF Diff                                                    │
├───────────┬──────────────────────────────────────────────────┤
│           │  [Inspector] [Compare]    (mode/sensitivity/nav) │
│ Documents │──────────────────────────────────────────────────│
│           │                                                  │
│ ▸ doc1.pdf│  (detail area: InspectorView or CompareView)    │
│ ▸ doc2.pdf│                                                  │
│ ▸ doc3.pdf│                                                  │
│           │                                                  │
│           │                                                  │
│───────────│──────────────────────────────────────────────────│
│ [Compare] │  (bottom panel: metadata or diff summary)        │
└───────────┴──────────────────────────────────────────────────┘
```

- **Sidebar** — always visible, lists opened documents
- **Top bar** — segmented control for Inspector/Compare tab. When in Compare: mode picker, sensitivity, page nav
- **Detail area** — swaps between InspectorView and CompareView
- **Bottom panel** — Inspector mode: MetadataPanel. Compare mode: DiffSummaryPanel

---

## Compare Mode — Document Slots

When Compare tab is active, the top of the compare area shows two document slots:

```
┌─────────────────────────────────────────────────────┐
│  [Left Document]     ⇄     [Right Document]         │
│  ┌────────────────┐       ┌────────────────┐        │
│  │ brochure_v1.pdf│       │ Drop PDF here  │        │
│  │ drag to swap   │       │ or select in   │        │
│  │            [×] │       │ sidebar        │        │
│  └────────────────┘       └────────────────┘        │
├─────────────────────────────────────────────────────┤
│  (compare visualization)                            │
```

### Entry points to compare mode

1. **Drag from sidebar** — drag document onto Left or Right slot
2. **Multi-select + Compare button** — Cmd+click two docs in sidebar, click "Compare" button at sidebar bottom. First selected goes Left, second goes Right.
3. **Auto-enter** — dropping/opening exactly 2 PDFs at once auto-enters Compare mode with both assigned

### Slot behaviors

- Empty slot: dashed border, "Drop PDF here" prompt
- Filled slot: filename, small × to clear
- ⇄ button between slots to swap Left/Right
- Changing either slot re-triggers the diff automatically

---

## Compare Visualizations

Mode picker in toolbar: `[Overlay] [Side by Side] [Swipe] [Onion Skin]`

### Overlay (default) — animated auto-toggle

The classic prepress blink comparison. Alternates between left and right page image at a steady interval.

- **Default blink interval:** 0.8 seconds
- **Controls:**
  - Play/Pause button to stop animation and freeze on one side
  - Speed slider (0.3s – 2.0s)
  - When paused: Left/Right toggle buttons for manual flip
- Pixel differences "jump" visually between frames

### Side by Side

- Left and right pages in HStack
- Synced scroll position — both zoom and pan together

### Swipe

- Draggable vertical divider
- Left image clipped to left of divider, right image to right
- Good for registration and color shift checks

### Onion Skin

- Both images overlaid
- Opacity slider: 0% = left only, 100% = right only

### Shared across all modes

- Page navigation (prev/next) synced across both documents
- Sensitivity slider (controls pixel diff threshold) — visible in toolbar for all modes

---

## Diff Summary Panel

Bottom panel in compare mode. Replaces metadata panel.

```
┌─────────────────────────────────────────────────────┐
│ Similarity: 99.2%  ████████████████████░            │
│                                                     │
│ ▾ Pixel Changes           3,241 of 501,760 px      │
│   ▸ Region 1  (124×86 at 340,220)                  │
│   ▸ Region 2  (56×34 at 102,680)                   │
│                                                     │
│ ▾ Text Changes (1)                                  │
│   Page 3: "Pantone 485C" → "Pantone 485 C"         │
│                                                     │
│ ▸ Font Changes (0)                                  │
│ ▸ Page Size Changes (0)                             │
│ ▸ Metadata Changes (0)                              │
└─────────────────────────────────────────────────────┘
```

- Clicking a region scrolls/zooms the compare view to that area
- Sections with changes auto-expand, sections without stay collapsed
- Similarity color-coded: green (>99%), yellow (90-99%), red (<90%)

---

## Changes to Existing Code

| Area | Current State | Change |
|------|--------------|--------|
| AppView detail area | Only InspectorView | Add segmented tab, swap Inspector/Compare |
| Sidebar | Single selection | Add multi-select, "Compare" button at bottom |
| CompareView | Built, unreachable | Wire into detail area, add document drop slots at top |
| Overlay mode | Static diff bitmap | Replace with animated blink between left/right |
| CompareViewModel | Functional, unused | Hoist to AppView level so sidebar can populate it |
| DiffSummaryPanel | Built, unreachable | Wire into compare mode bottom panel |
| InspectorViewModel.Tab | Unused enum | Remove — tab switching lives at AppView level |
| MockPDFService | PDFKit-based, works | No change |

No new Rust code needed. All changes are SwiftUI.
