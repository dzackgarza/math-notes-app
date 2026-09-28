# Core note-taking features

The standard feature set of stylus-first handwriting apps, in layers, with
the state of each feature in Math Notes. The survey read the feature and help
documentation of GoodNotes 6, Notability, Noteful, Samsung Notes, OneNote,
Apple Notes, Xournal++, Saber, Stylus Labs Write, and Flexcil (2026-09-28).
Handwriting recognition and conversion are outside the product
([AGENTS.md](../../AGENTS.md#product-boundary-handwritten-drafts)).

| Layer | Meaning |
| --- | --- |
| L0 | In essentially every app. One real note-taking session fails without it. |
| L1 | In most apps. Expected for daily use. |
| L2 | Common but secondary. |
| L3 | Distinctive to one or two apps. |

Work proceeds by layer. A layer starts only when every feature of the
earlier layers exists and works in the deployed app.

## L0

| Feature | Math Notes |
| --- | --- |
| Pen with color and width choice | Exists. |
| Pressure-sensitive ink | Exists (Google Ink pressure pen). |
| Highlighter drawn beneath the ink | Exists (`core/src/editor/editor.cpp`, as Write's DRAW_UNDER). |
| Stroke eraser | Exists. |
| Freehand lasso: move, delete, cut, copy, paste | Exists. |
| Undo and redo: toolbar buttons, rewind dial, and Ctrl+Z | Exists. A drag on the undo button turns the rewind dial (`hosts/web/flutter/lib/undo_dial.dart`, from Write's `ButtonDragDial`). |
| Pen draws; one finger pans | Exists. |
| Palm rejection: a resting hand neither draws nor moves the page during a stroke | Exists (`PalmRejection` in `hosts/web/flutter/lib/notebook.dart`). |
| Pinch zoom | Exists. |
| Multi-page document, vertical page stack | Exists. |
| Add and delete a page | Exists: held pull at the end, the **Pages** and **⋯** menus, and the page overview. |
| Ruled, grid, dotted, and blank paper | Exists. |
| Autosave and reopen | Exists. |
| Library with folders | Exists. |
| PDF export | Exists. |

## L1

| Feature | Math Notes |
| --- | --- |
| One toolbar tool per kind; saved pens as toolbar shortcuts | Exists. Tool settings and saved pens persist in `.pens.json`. |
| Tool popover: stroke sample, pen types, size presets, slider, advanced tab | Exists. A tap on the selected tool opens it. |
| Touch color picker and customizable palette | Exists: an HSV wheel (`flex_color_picker`) edits a swatch; **+** edits the palette. |
| Dark app chrome; floating icon toolbar; top-right pull-down menus | Exists (`pull_down_button`). |
| Partial eraser | Exists. |
| Two-finger tap undo; three-finger tap redo | Exists (`FingerTap` in `hosts/web/flutter/lib/notebook.dart`). |
| Stylus eraser end or side button switches to the eraser | Exists. A stroke begun with the side button held erases until the pen lifts. |
| Finger-drawing toggle | Exists. One finger draws, two fingers pan and zoom, and a second finger cancels the stroke in progress. The choice persists. |
| Rectangle select; oval select | Exists. |
| Selection resize | Exists (handles). |
| Selection recolor | Exists: a palette swatch recolors the selection (`ink_canvas_recolor_selection`). |
| Selection duplicate | Exists. |
| Page overview: thumbnail grid with drag reorder, duplicate, delete | Exists: **Pages** (`hosts/web/flutter/lib/pages_sheet.dart`, on `reorderable_grid`). |
| Page size and orientation | Exists: A4 or Letter, portrait or landscape, at creation and for new pages. |
| Rename, move, and trash notes | Exists. |
| Title search | Exists. |
| PDF import and annotation | Exists. |
| Image insert | Exists. |
| Typed text box | Exists. |

## L2 and L3

Present in Math Notes: bookmarks and links, layers, clippings (Write),
split view, conflict comparison, insert space, ruled select and erase and
cross-page reflow (Write), and TikZ skeleton extraction. They receive no work
until L0 and L1 are complete.

Absent L2 features: zoom window, double-tap zoom, shape tool, return to the
previous tool after erasing, erase highlighter only, page rotate, image export.

## Reference implementation

[Saber](https://github.com/saber-notes/saber) is an open-source Flutter
handwriting app covering L0 and most of L1. Its canvas is a fork of Flutter's
`InteractiveViewer` whose gesture start decides between a stroke and a
pan/zoom; a second pointer rejects the gesture and removes the stroke drawn so
far (`lib/components/canvas/interactive_canvas.dart`,
`lib/pages/editor/editor.dart` `isDrawGesture`). Its page manager is
a `ReorderableListView`.
