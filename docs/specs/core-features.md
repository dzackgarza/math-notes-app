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
| Undo and redo: buttons and Ctrl+Z | Exists. |
| Pen draws; one finger pans | Exists. |
| Palm rejection: a resting hand neither draws nor moves the page during a stroke | Exists (`PalmRejection` in `hosts/web/flutter/lib/notebook.dart`). |
| Pinch zoom | Exists. |
| Multi-page document, vertical page stack | Exists. |
| Add and delete a page | Exists: **Add page**, held pull at the end, **Page** menu. |
| Ruled, grid, dotted, and blank paper | Exists. |
| Autosave and reopen | Exists. |
| Library with folders | Exists. |
| PDF export | Exists. |

## L1

| Feature | Math Notes |
| --- | --- |
| Pen presets | Exists: Pen, Thick pen, Highlighter. |
| Pen settings popover: preview, size presets, slider, full color picker | Missing. A centered alert with six colors. |
| Partial eraser | Exists. |
| Two-finger tap undo; three-finger tap redo | Missing. |
| Stylus eraser end or side button switches to the eraser | Eraser end exists. Side button missing. |
| Finger-drawing toggle | Missing. |
| Rectangle select | Exists. |
| Selection resize | Exists (handles). |
| Selection recolor | Missing. |
| Selection duplicate | Exists. |
| Hold at the end of a stroke to snap it to a line or shape | Missing. |
| Page overview: thumbnail grid with drag reorder, duplicate, delete | Missing. The **Page** menu moves the current page up or down and deletes it. |
| Page size and orientation | Size exists (A4, Letter). Orientation missing. |
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
`lib/pages/editor/editor.dart` `isDrawGesture`). It snaps shapes with
`one_dollar_unistroke_recognizer` after a 500 ms hold, and its page manager is
a `ReorderableListView`.
