# Feature spec

Math Notes is a vector handwriting app for mathematics notes and talks. Its
features come from [Stylus Labs Write](https://github.com/styluslabs/write):
notes are SVG files on the ordinary filesystem, and ink is reflowable. Its
look and everyday interaction follow GoodNotes and Noteful, as specified in
[specs/tablet-ui.md](specs/tablet-ui.md); nothing visual comes from Write.
Plain SVG pages remain readable by external programs. Drawing mode also
interprets captured ink as an editable mathematical figure.

The tablet interface (layout, controls, style) is in
[specs/tablet-ui.md](specs/tablet-ui.md).
The [component-ownership contract](ARCHITECTURE.md#component-ownership)
governs implementation of every feature, including ink editing and reflow.

## Base: keep from Write

These define the app. New features must not break them.

- Native format is a directory of standalone SVG pages ([FORMAT.md](FORMAT.md)).
- Discrete fixed-size pages, one printed sheet each; A4 by default, size set
  per notebook. No infinite canvas.
- The pen draws; fingers pan and zoom.
- Sync conflict copies of pages are detected and resolved side by side
  ([FORMAT.md](FORMAT.md)).
- Handwriting-aware reflow: line, word, and column structure of ink.
- Insert horizontal and vertical space into existing ink.
- Ruled erase and ruled select.
- Lasso select, move, resize of ink.
- Bookmarks placed in the ink, and links inside and between documents.
- Clippings library.
- Split view of two documents.
- SVG page backgrounds (paper color, lined, grid, dotted) and templates.
- Configurable pressure-sensitive pens and highlighter, with original samples
  retained in the note. The selected replacement uses Write `StrokeBuilder`
  and its matching free-erase path; see the [ink ownership decision](ink-reflow-owners.md).
- Unlimited undo and redo.
- PDF export.
- Folders on the filesystem are the library. Sync is the filesystem's job (iCloud Drive,
  Dropbox, Nextcloud, git through Files). The free Apple Account cannot use the
  iCloud entitlement, so the app must not need it.

## Features to add, in priority order

| # | Feature | Requirement | Mechanism |
| --- | --- | --- | --- |
| 1 | PDF annotation | Open a PDF from Files or the share sheet. Import renders each PDF page to a PNG 4128 px wide (2× the 2064 px portrait width of a 13-inch iPad Pro); that image is the page background, and ink goes on top. Each page keeps the size of its PDF page. After import the app does not use the PDF. Blank pages can be inserted between imported pages. Export writes the pages, background images and ink, to a new PDF. | Host rasterizer at import (web: Artifex's `mupdf` WASM package in a Web Worker; iPad: PDFKit); Skia PDF backend at export; share sheet and file picker in the hosts |
| 2 | User-visible layers | Create, name, hide, show, reorder, and lock layers per notebook. The layer list is in `notebook.json`; each page stores one SVG `<g>` per layer. Export can include or exclude each layer. | SVG groups ([FORMAT.md](FORMAT.md)) |
| 3 | TikZ drawing mode | Toggle the mode on to capture figure ink; toggle it off to complete one bounded, editable figure. Preserve its strokes, geometric scene, and authored TikZ. Show the figure and source in a preview sidebar. Reopening the figure restores editing. See [the drawing-mode specification](specs/tikz-drawing-mode.md). | A fork of FreeTikZ, with a persistent scene graph and source-preserving TikZ editing |

## Out of scope

Managed cloud sync, account libraries, AI summarization and chat, flashcards,
sticker and template stores, real-time collaboration.
