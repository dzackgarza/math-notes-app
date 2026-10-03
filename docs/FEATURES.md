# Feature spec

Math Notes is a vector handwriting app for mathematics notes and talks. Its
features come from [Stylus Labs Write](https://github.com/styluslabs/write):
notes are SVG files on the ordinary filesystem, and ink is reflowable. Its
look and everyday interaction follow GoodNotes and Noteful, as specified in
[specs/tablet-ui.md](specs/tablet-ui.md); nothing visual comes from Write.
Plain SVG pages remain readable by external programs. Drawing mode also
extracts a reusable TikZ skeleton from captured diagram geometry.

## Product scope

This application stores handwritten drafts. Typeset papers and polished
figures belong to external authoring tools. Notebook pages and exports retain
the visible handwriting.

LaTeX notebook export, LaTeX page rendering, handwriting/OCR/formula
recognition, and LaTeX label entry are outside the product. They are not
future milestones. Diagram extraction does not convert handwritten labels
or mathematical expressions into source text.

TikZ mode supplies a starting diagram for later work: capture a doodle,
extract its geometric structure, select it, and copy a TikZ skeleton into
the paper-writing pipeline or an external TikZ editor. Final labels, layout,
and typesetting are completed there.

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
- Spatial ink reflow: line, word-gap, and column layout, without recognizing
  written content.
- Insert horizontal and vertical space into existing ink.
- Ruled erase and ruled select.
- Lasso select, move, resize of ink.
- Bookmarks placed in the ink, and links inside and between documents.
- Clippings library.
- Split view of two documents.
- SVG page backgrounds (paper color, lined, grid, dotted) and templates.
- Configurable pressure-sensitive pens and highlighter, with original samples
  retained in the note. The v1 engine uses Google Ink for brush geometry and
  keeps the editable stroke in the Math Notes document model.
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
| 3 | TikZ drawing mode | Capture doodled diagram geometry and extract a reusable TikZ skeleton. Select the diagram and copy its code for refinement in an external authoring tool. Preserve handwritten ink and its association with the source through save and reopen. See [the drawing-mode specification](specs/tikz-drawing-mode.md). | FreeTikZ capture and supported TikZ geometry/source operations |

## Out of scope

Sync between devices by the app, managed cloud sync, account libraries, a
zoom window (the magnified writing strip of Noteful), AI summarization and
chat, flashcards, sticker and template stores, real-time collaboration.
