# Storage and file format

The authoritative state is an ordinary directory tree of documented,
standard files at a location the user chooses. The app has no private library
and no sync of its own. Saving writes the file in place; whatever owns the
directory (Dropbox, iCloud Drive, Nextcloud, git, rsync) moves it from there.

## Invariants

1. Every page is a valid standalone SVG file, and opening it in a browser
   with no app code shows the ink and the background.
2. Every other object is a file in a documented standard format (PNG,
   JPEG, SVG, JSON, InkML inside SVG metadata).
3. The notebook is fully rebuilt from its directory. Caches (thumbnails,
   render caches) are disposable, and deleting them loses nothing.
4. Saves edit files in place at their existing paths. No import or export
   step stands between the user and the files.
5. Saving the same document twice gives the same bytes, on every host.

## Layout

The folder hierarchy is the organization. The app discovers it on every
scan; a notebook moved or renamed by any other tool is simply found at its
new path. A directory is a notebook when it holds a `notebook.json`.

```text
Notes/                         root the user picked
├── .pens.json                 pen presets, shared by all devices
├── .library.json              library metadata: tags, favorites, descriptions
├── .templates/                page templates (notebook directories)
├── .clippings/                clippings library (a notebook directory)
├── .trash/                    notebooks deleted in the app
└── Algebraic Geometry/
    └── stable-pairs/          one notebook = one directory
        ├── notebook.json
        ├── pages/
        │   ├── 0001.svg
        │   └── 0002.svg
        └── assets/
            ├── p0017.png
            └── diagram.png
```

`notebook.json`:

```json
{
  "format": "math-notes",
  "version": 1,
  "title": "Stable pairs",
  "pageSize": "A4",
  "template": "lined-medium",
  "layers": [
    { "id": "l-8f3kq0", "name": "Ink", "hidden": false, "locked": false }
  ],
  "pages": [
    { "id": "p-c718xa", "file": "pages/0001.svg" },
    { "id": "p-9a02mm", "file": "pages/0002.svg" }
  ]
}
```

- `pageSize` is `"A4"`, `"Letter"`, or `[width, height]` in points. It is the
  size of new pages. Each page SVG carries its own size.
- `layers` is the notebook's layer list, bottom to top. A notebook has at
  least one layer.
- `pages` gives the page order. Moving a page reorders this array; files
  are never renamed. Deleting a page removes its entry and its file.
- Keys are written in the order shown, two-space indent, one trailing
  newline.

One file per page, so a stroke on page 217 changes only `pages/0217.svg`:
sync moves one small file, and two devices editing different pages do not
conflict. Assets are separate files, not base64 inside SVG.

### Page files

- A new page file gets the next unused four-digit number in `pages/`
  (after `0009.svg` comes `0010.svg`, whatever its position). Its name never
  changes after creation.
- A file in `pages/` that `notebook.json` does not list is shown after the
  listed pages and marked as unlisted. The app never deletes it on its own.
- A file in `pages/` that does not parse as SVG (for example, one with git
  merge-conflict markers) is shown as an error page with the parser message.
  The app never writes over it; the user fixes or deletes it outside the
  app.

## Page SVG

```xml
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:mn="https://github.com/dzackgarza/math-notes-app/ns/1"
     xmlns:inkml="http://www.w3.org/2003/InkML"
     id="p-c718xa" width="210mm" height="297mm" viewBox="0 0 595.28 841.89">
  <metadata>
    <inkml:traceFormat xml:id="xytfa">…</inkml:traceFormat>
  </metadata>
  <g id="background" mn:ruling="lined" mn:y-ruling="19.2"
     mn:y-offset="57.6" mn:x-ruling="0" mn:margin-left="48">
    <rect width="595.28" height="841.89" fill="#FCFAF5"/>
    <path d="…" fill="none" stroke="#C9D3E0" stroke-width="0.6"/>
  </g>
  <g id="l-8f3kq0">
    <path id="s-3kd92lq0mzpa" transform="translate(12.5,-4)"
          fill="#1A1A1A" mn:brush="pressure-pen" mn:brush-version="1"
          mn:size="1.6" mn:time="2026-09-25T17:43:21.123Z"
          d="M104.2 51.37l0.4 -0.12…Z">
      <metadata><inkml:trace contextRef="#xytfa">…</inkml:trace></metadata>
    </path>
  </g>
</svg>
```

- Only core SVG elements: `path`, `g`, `image`, `text`, `tspan`, `a`, `rect`, `line`,
  `polygon`, `ellipse`, `circle`, `metadata`, transforms. No
  `foreignObject`, no `<style>`, no `<use>` across files.
- Units: the `viewBox` is in PostScript points (1/72 inch), the unit of PDF
  pages and of PDF export. `width` and `height` are in `mm`, so the file
  prints at its physical size. A4 is 595.28 × 841.89 pt.
- Element order: `metadata`, then `g#background`, then one `g` per layer in
  `notebook.json` order, with the layer id as its `id`.
- A stroke is a filled `path` whose `d` is the brush outline: every outline
  of the stroke is a closed subpath, with nonzero fill. A constant-width
  stroke can use an SVG stroked path. Preserve the selected ink owner's
  path commands and brush classes so its eraser can edit the same element.
  Both forms display in a standard SVG renderer.
- A typed text box is an SVG `text` element with `x`, `y`, `font-size`,
  `font-family`, and `fill`. Each line is a `tspan`; its baseline and the
  later lines' `dy` values come from Skia Paragraph with
  the same bundled font bytes and layout properties used for rendering. Its `transform`
  stores a move or resize. The first `y` is the text baseline. Preserve the
  authored text and its explicit line breaks through layout and save.
- The stroke's input samples are an [InkML](https://www.w3.org/TR/InkML/)
  `trace` in the path's `metadata`. The page's root `metadata` declares one
  `inkml:traceFormat` per channel set that its strokes use. Channels, in
  this order when present: `X`, `Y` (pt), `T` (ms from `mn:time`), `F`
  (force 0..1), `OE` (altitude, rad), `OA` (azimuth, rad), `OR` (roll, rad).
  Every value is written in full: points separated by `,`, channels by one
  space. This is the form that existing InkML readers take, among them
  Wacom's universal-ink-library, microsoft/InkMLjs, and the CROHME
  handwritten-math tools, so external scripts can read the samples of any
  page.
- Stroke attributes, in this order: `id`, `transform`, `fill`, `fill-opacity`,
  `mn:brush`, `mn:brush-version`,
  `mn:size`, `mn:time`, `d`. `mn:brush` names the ink owner's brush
  family and `mn:brush-version` its pinned encoding version. The owner and
  source-fidelity extension are fixed in [ARCHITECTURE.md](ARCHITECTURE.md).
  A library update must preserve the stored outline. `mn:time` is the UTC
  start time of the stroke.
- `d` and the samples are in stroke-local coordinates. Moving, resizing, or
  rotating a stroke writes only its `transform` attribute
  (`translate(x,y)` or `matrix(a,b,c,d,e,f)`).
- The engine regenerates a stroke's outline only when the stroke is created
  or its samples or brush change. A loaded outline is written back as it was
  read.
- IDs: `p-` pages, `l-` layers, `s-` strokes, `b-` bookmarks, `f-`
  figures. Each is the prefix plus 6 (pages, layers) or 12 (strokes,
  bookmarks, figures) characters of lowercase base32 from a seedable generator.
  Reordering or renaming never changes an id. A pasted element whose id
  already exists on the page gets a new id.
- Clipboard: copy and cut write the selected elements as a standalone page
  SVG (`id="clipboard"`, one layer, the elements at their page coordinates),
  which the host keeps as text on the system clipboard. Copied elements get
  new ids; cut ones keep theirs.
- Numbers: coordinates, sizes and translations with 2 decimals; a matrix's
  `a`, `b`, `c`, `d` with 6 decimals (a scaled or rotated stroke then stays
  within 0.001 pt anywhere on the page); force and angles with 3 decimals; `T` in whole milliseconds. Written with
  `std::to_chars` fixed format, `-0` written as `0`, trailing zeros removed.
  `d` retains the ink owner's SVG path commands, including curve controls. Colors are
  `#RRGGBB` in upper case; opacity goes in `fill-opacity`.
- XML is written one element per line, two-space indent, attributes in the
  orders above. No generated thumbnails in the file. Diffs, git, and sync
  history stay readable.

### Background

- `g#background` holds the page's paper: a filled `rect` and the ruling
  lines, drawn as ordinary SVG so any viewer shows them.
- `mn:ruling` is `blank`, `lined`, `grid`, or `dotted`. `mn:y-ruling` (line
  spacing), `mn:y-offset` (y of the first line), `mn:x-ruling` (grid
  spacing, 0 when none) and `mn:margin-left` are in points. Ruled select,
  ruled erase, reflow, and insert space read their line positions from
  these attributes. A `blank` page uses a line spacing of 28.8 pt, anchored
  at the pen-down point (Write's `blankYRuling`).
- An imported PDF page is an `<image>` of its PNG in `assets/`, inside
  `g#background` after the paper `rect` and before the ruling.
- A new page copies the background of the notebook's `template`.

### Links and bookmarks

- A bookmark is a `g` with an id `b-…` and `class="mn-bookmark"` around the
  bookmarked ink, or around a flag path drawn in the left margin.
- A link is an SVG `a` element around the linked ink. Its `href` is a URL,
  or a path relative to the page file plus a fragment:
  `0003.svg#b-2kq9…` for a page of the same notebook,
  `../../MMP/flips/pages/0001.svg#b-…` for another notebook. The link then
  works in a browser that opens the page file, and keeps working when the
  whole tree moves.

### TikZ figures

One Drawing mode session completes as one figure. Its page element is a group
with stable `f-` id, `class="mn-figure"`, optional `transform`, and
`mn:scene` and `mn:tikz` paths relative to the page file. The group contains
the current vector view of the figure as ordinary SVG children. A browser
that opens the page file draws those children without loading either sidecar.
The group is one selectable page object; its children are edited through the
figure editor, not as separate page strokes.

```xml
<g id="f-c718xa2kq9mz" class="mn-figure"
   mn:scene="../assets/f-c718xa2kq9mz.scene.json"
   mn:tikz="../assets/f-c718xa2kq9mz.tikz">
  <path id="s-3kd92lq0mzpa" ...>
    <metadata><inkml:trace contextRef="#xytfa">…</inkml:trace></metadata>
  </path>
</g>
```

The `.scene.json` file is the forked FreeTikZ scene: stable object ids,
original pen samples, interpreted geometric objects, and their relations.
The `.tikz` file holds the exact TikZ source, including user edits. A canvas
edit changes only the source range owned by that operation. A page save must
not regenerate the `.tikz` file from the scene. A scene edit updates the
group's vector children so page SVG, thumbnails, and PDF export show the
current figure. Figure move and resize change the group transform and bounds
together. Copy gives the figure and its sidecars new ids and paths. Deleting
the last reference deletes the sidecars as part of the notebook save.

Both sidecars belong to the notebook's `assets/` directory and follow the
same in-place save and dirty-file contract as page files. A missing or invalid
sidecar is an explicit figure error; the page's visible SVG children remain
available for viewing and recovery.

Plain `.svg` only; `.svgz` is not written. ZIP is only a transport form of
a notebook directory (send, archive, download).

## Other files

- `Notes/.pens.json`: the pen presets, an array of
  `{ "id", "name", "brush", "brushVersion", "color", "opacity", "size" }`,
  in toolbar order, with the keys in this order, two-space indent and one
  trailing newline. `brush` and `brushVersion` are as `mn:brush` and
  `mn:brush-version`; `color` is `#RRGGBB`; `opacity` (0 to 1, 3 decimals)
  becomes the strokes' `fill-opacity`; `size` is in points (2 decimals).
  Numbers have no trailing zeros. The app writes these presets on first use:

  ```json
  [
    {
      "id": "black-pen",
      "name": "Black pen",
      "brush": "pressure-pen",
      "brushVersion": 1,
      "color": "#1A1A1A",
      "opacity": 1,
      "size": 1.2
    }
  ]
  ```

  followed by `blue-pen` (`#1F4FB5`), `red-pen` (`#B51F1F`), `marker`
  (`marker`, `#1A1A1A`, 2.4 pt) and `highlighter` (`highlighter`, `#FFE066`,
  opacity 0.35, 9.6 pt). A stroke keeps the brush, color, opacity and size
  it was drawn with; editing a preset changes only later strokes.
- `Notes/.templates/<name>/`: a notebook directory. Page 1's background is
  the template. The app creates `blank`, `lined-wide`, `lined-medium`,
  `lined-narrow` (y-ruling 21.6, 19.2, 16.8 pt; margin 48 pt),
  `grid-coarse`, `grid-medium`, `grid-fine` (16.8, 14.4, 9.6 pt) and
  `dotted` (16.8 pt) on first use, with Write's ruling spacings. Paper is
  `#FCFAF5`; rules and dots are `#C9D3E0`, the margin `#E8A0A0`. Rules are
  0.6 pt wide; dots are 1.5 pt zero-length subpaths with
  `stroke-linecap="round"`.
- `Notes/.library.json`: the library metadata of the tablet interface
  ([specs/tablet-ui.md](specs/tablet-ui.md)). Keys in this order, two-space
  indent, one trailing newline:

  ```json
  {
    "format": "math-notes-library",
    "version": 1,
    "tags": [{ "name": "Research", "color": "#2F6FEB" }],
    "notes": {
      "Algebraic Geometry/stable-pairs": {
        "favorite": true,
        "tags": ["Research"],
        "description": "Outline of the proof and key references."
      }
    },
    "folders": {
      "Algebraic Geometry": {
        "description": "Notes on moduli and geometry.",
        "paper": "grid-medium",
        "coverColor": "#A9C1F5",
        "coverStyle": "spine",
        "tags": ["Research"]
      }
    },
    "startingTemplates": [{
      "name": "Seminar notes",
      "folder": ["Algebraic Geometry"],
      "paper": "grid-medium",
      "pageSize": "letter",
      "tags": ["Research"]
    }],
    "draft": {
      "folder": ["Algebraic Geometry"],
      "title": "Derived categories",
      "template": "grid-medium",
      "tags": ["Research"],
      "pageSize": "letter"
    }
  }
  ```

  `tags` is the tag list in sidebar order. `notes` is keyed by a note
  directory's path from the root, `/`-separated. `folders` is keyed by a
  notebook folder's path from the root and sets its new-note paper, cover,
  description and tags. `startingTemplates` holds named New Note settings.
  Folder paths in these entries follow folder renames and moves. Keys whose
  directory is no longer at that path are ignored. `draft` holds the New Note fields until the note is created. The
  file is absent until the first notebook, tag, favorite, description or draft
  is set.
- `Notes/.clippings/`: a notebook directory; each page is one clipping,
  sized to its content.

## Access per host

| Host | Access to the notebook root |
| --- | --- |
| iPad | Files folder picker (`UIDocumentPickerViewController` for folders). A File Provider works when it supports folder picking; Dropbox has since May 2024. The app keeps a `.minimalBookmark` bookmark, created while access is started, and refreshes it when stale. Reads and writes go through `NSFileCoordinator`; a page is written with `Data.write(options: .atomic)`. One `NSFilePresenter` on the root reports external changes. |
| Web, Chrome | `showDirectoryPicker({mode: "readwrite"})`; the directory handle is kept in IndexedDB and re-permitted on launch through a "Reconnect folder" button. Writes use `createWritable({mode: "exclusive"})`. Scans skip `*.crswap` files. Renaming or moving a directory copies it, then removes the original: the API has no directory move. |

OPFS and IndexedDB hold only caches, never notes.

## Sync conflicts

The app detects conflicts in three ways, and never merges silently.

1. **A conflict copy by file name**, for a page or for `notebook.json`:

   | Provider | Name of the copy of `0007.svg` |
   | --- | --- |
   | Dropbox | `0007 (<user>'s conflicted copy YYYY-MM-DD).svg` |
   | Nextcloud | `0007 (conflicted copy [<user> ]YYYY-MM-DD HHMMSS).svg`, or `0007 (case clash from …).svg` |
   | Syncthing | `0007.sync-conflict-YYYYMMDD-HHMMSS-<7-char device id>.svg` |
   | iCloud Drive (two devices create the same new file) | `0007 2.svg` |
   | OneDrive | `0007-<device name>.svg` |
   | Google Drive for desktop | `0007 (1).svg` |

   Independent of the provider: a file in `pages/` that `notebook.json` does
   not list, and whose name starts with the base name of a listed page, is a
   conflict copy of that page. The table only labels the provider.
2. **An iCloud edit conflict** creates no file: iCloud keeps the other
   versions as `NSFileVersion`s. The iPad host checks
   `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` for every page and
   for `notebook.json` it loads.
3. **A page that does not parse** (see Page files).

A conflicted notebook is marked in the library. The resolution view shows
the two versions side by side with linked scrolling and zoom, and offers:
keep one, keep both as separate pages, or copy strokes from one into the
other. For `notebook.json` it shows the two page orders and layer lists and
the user keeps one; pages listed in neither become unlisted pages. Resolving
deletes the losing file (or marks the `NSFileVersion` resolved).

## Write comparison corpus

The user's Write notes are in `~/Downloads/Original Notes.zip` (ten
`write-v3` `.svgz` documents). They serve only to compare behavior against
Write by hand, and stay out of this public repository. The fixtures in
`tests/fixtures/write/` are recorded from synthetic input.

## Conventions

- Undo history is kept for the open session only.
- Pens, templates, and clippings live under the notes root, so every device
  that opens the root sees the same ones.
