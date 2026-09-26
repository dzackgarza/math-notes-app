# Tablet interface

The target interface for the web app and the iPad app on a tablet-sized
screen. The four mockups below are the reference for layout, controls and
visual style. They are illustrations: the handwriting, names, counts and dates
in them are sample content, and the app is Math Notes. Phone layouts are not
specified. Where the mockups leave something open, GoodNotes and Noteful
are the reference for look and interaction.

## Screens

### Library

![Library](ui/tablet-library.png)

- **Sidebar**, always visible: app mark and name; Library, Search, Recent,
  Favorites, Trash; a Tags list with a color and a count per tag, and
  **+** to add a tag; Settings at the bottom.
- **Main pane**: title "Library" and a one-line description; **New Notebook**
  (secondary) and **New Note** (primary) buttons; a search field; a filter
  menu ("All Notebooks"); a sort menu ("Last Modified"); a grid/list toggle.
- **Notebook cards** in a grid: a thumbnail of handwritten content, the
  title, the note count, "Modified …", tag chips, and a **⋯** menu. The
  selected card has a blue outline.
- **Detail pane** for the selected notebook: a large thumbnail, title, note
  count, modified time, tag chips with **+**, **Notes** and **Info** tabs, a
  note search field, and the note list (thumbnail, title, a one-line
  summary, modified time), ending with **New Note in <notebook>**.

### New Notebook

![New Notebook](ui/tablet-new-notebook.png)

- **Cancel** at the top left, **Create Notebook** (primary) at the top right.
- Fields: Notebook Title; Description (optional, 500-character counter);
  Paper Style (Dot, Graph, Blank, Ruled, each with a preview tile); Tags
  (removable chips and "Add a tag…"); Location (a folder menu, "You can move
  this notebook later").
- **Preview** of the cover, and **Notebook Details** summarizing paper,
  location and tag count. A cover is a preview of the notebook's first page,
  here and on every card.

### New Note

![New Note](ui/tablet-new-note.png)

- **Cancel**; title "New Note in <notebook>"; the target notebook's
  thumbnail with **Change Notebook**.
- Fields: Title; Paper Style (Dot, Grid, Lined, Plain, Graph); Tags; Starting
  Template (Blank Note, Theorem / Proof, Grid Sketch, Lecture Notes) with a
  one-line description of the selected template.
- A large live preview of the first page with the paper and template.
- **Save as Draft** and **Create Note** (primary) at the bottom right.

### Editor

![Editor](ui/tablet-editor.png)

- **Top bar**: app mark; notebook title with a menu and a subtitle; a tab
  per open note with close buttons, and **+**; share and **⋯** at the right.
- **Tool rail** on the left: Pen, Thick Pen and Highlighter, each with its
  size; Eraser; Lasso; Drawing mode; then a color palette of 15
  swatches and **+**.
- **Page** fills the rest: dot paper, a handwritten title, tag chips with
  **+**, and ink with highlighter boxes, color and drawings.
- **Bottom bar**: undo and redo; a zoom menu ("100%"); a paper menu ("Dot
  Paper"); a page indicator "1 / 12" with previous and next.

## Pages in the editor

- Pages have a 6 pt desk-colored gap between them. In the default view a page
  fills the full width of the canvas.
- One finger pans the pages. Two fingers pinch to zoom. Pen input draws.
- On the web, Framework7 9.1.2 `page-content` owns the editor viewport's
  browser scroll and bottom-pull motion. On iPad, `UIScrollView` and
  MJRefresh 3.7.9 `MJRefreshBackFooter` own the same native behavior. A held
  ready state followed by release issues one add-page command; the notebook
  supplies the new page and its template. Framework7 and MJRefresh keep their
  motion, resistance, release, and boundary behavior. The browser uses
  `@use-gesture/vanilla` 10.3.1 for pinch recognition. The
  [UI ownership decision](../research_notes/Component%20ownership%20decisions/ui.md)
  gives the component contracts and same-surface pen/finger input boundary.
- Ink cannot land outside a page. On pen-up, the parts of the stroke outside
  its page are removed (Noteful's behavior); a stroke entirely outside is
  removed.

## Visual style

Both hosts use complete iOS-style controls: SwiftUI and UIKit on the iPad,
Ionic in iOS mode on the web. Their behavior and accessibility belong to the
components identified in [ARCHITECTURE.md](../ARCHITECTURE.md#component-ownership).
The colors below are Ionic theme variables. App CSS supplies document layout
and theme values.

Light theme, white and very light gray panels, one blue accent (#2F6FEB,
approximately) for primary buttons, selection and links. Rounded cards and
chips, thin gray borders, system sans-serif type. Paper is warm off-white.

## Relation to the current model

| Mockup | Current model ([FORMAT.md](../FORMAT.md), [FEATURES.md](../FEATURES.md)) |
| --- | --- |
| Paper Style, Starting Template (backgrounds) | Built-in templates: blank, lined-*, grid-*, dotted (#21) |
| Pen, Highlighter, color palette | Pen presets (#25); Write `StrokeBuilder` in the selected replacement architecture ([ink decision](../ink-reflow-owners.md)) |
| Eraser, Lasso, Drawing mode | #23, #24, [TikZ drawing mode](tikz-drawing-mode.md) |
| Undo and redo, zoom, page indicator | #22, #21 |
| Tabs of open notes | A tab per open note, as in GoodNotes and Noteful |
| Trash | `Notes/.trash/` |

The mockups add the following to FORMAT.md and FEATURES.md:

1. **A notebook contains notes, and this is the directory structure.** A
   mockup "notebook" is a folder; a mockup "note" is a FORMAT.md notebook
   directory.
2. **Metadata** (description, tags with colors, a one-line summary per note,
   drafts) lives in a JSON sidecar or in the app's internal database.
3. **Content templates** are saved settings: a named configuration of the
   new-note fields (paper, size, tags, and so on) that the user saves and
   reuses. The names in the mockup are sample content.
4. **Tabs** of open notes in the editor.
5. **Search, Recent, Favorites** are views of one table of notes: Search
   filters by title, Recent sorts by modification time, and Favorites filters
   by a favorite flag stored with the other metadata.
