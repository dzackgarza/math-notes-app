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

The mockup shows the page and the tabs. Noteful is the reference for the
toolbar and the tool popovers; `noteful-pen-tool.webp` shows its pen popover.

- **Top bar**: back to the library; the note title; a tab per open note with
  close buttons, and **+**. Three pull-down menus at the right:
  - **Pages**: page overview, bookmarks, and layers.
  - **View**: vertical scroll, horizontal scroll, or two-page layout;
    toolbar position (left or right); tab bar position (top or hidden).
  - **⋯**: paper for new pages (style, size, orientation); share and export
    PDF; go to page; clear page; delete page; gestures (finger drawing);
    customize the toolbar.
- **Toolbar**: one floating vertical bar of icons without text labels, one
  icon per tool kind: pen, marker, highlighter, eraser, lasso, text, image, insert
  space, drawing mode. Below a divider: undo, redo, saved pens, the color
  swatches, and **+**. The bar scrolls when its content is longer than the
  screen.
- **Tool popover**: a tap on the selected tool opens its popover. The
  popover edits the settings of that tool only and never changes the tool.
  - Pen, marker, and highlighter: a stroke sample drawn by the engine; five
    size presets and a size slider; an **Advanced** tab with opacity;
    **Save** keeps the current settings as a saved pen. Each tool has one
    brush: the pen draws with pressure, the marker with a constant width.
  - Eraser: stroke, partial, or ruled.
  - Lasso: freehand, rectangle, oval, or ruled.
- **Colors**: a swatch sets the color of the current pen or highlighter, or
  recolors the lasso selection when there is one. A tap on the selected
  swatch opens a touch color picker (an HSV wheel) that edits that swatch.
  **+** edits the list of visible swatches.
- **Saved pens**: as in Write, a saved pen is a toolbar shortcut that
  restores its tool (pen, marker, or highlighter) with its size, color, and
  opacity. It is not a new tool kind.
- **Undo and redo**: a tap undoes or redoes one step. A drag from the undo
  button turns a rewind dial around the button, as in Write
  (`ButtonDragDial` in `syncscribble/touchwidgets.cpp`): each dial step
  undoes or redoes one edit.
- **Page** fills the rest. Fit width keeps the current scroll position.

## Pages in the editor

- Pages have a 6 pt desk-colored gap between them. In the default view a page
  fills the full width of the canvas.
- One finger pans the pages. Two fingers pinch to zoom. Pen input draws.
- Flutter with Cupertino owns the complete web GUI and its input, focus,
  navigation, and controls. UIKit owns the independent iPad GUI.
  The [adopted framework decision](../reports/Web%20interface%20framework%20selection.md)
  defines the shared-core boundary.
- The notebook surface preserves framework-owned fling, edge resistance,
  rebound, and pinch navigation. On iPad, `UIScrollView` and MJRefresh 3.7.9
  `MJRefreshBackFooter` provide navigation and bottom pull. On web, Flutter
  owns the combined interaction. A held-ready release issues one add-page
  command; the notebook supplies the new page and template. Ordinary scrolling
  never adds a page. #56 verifies pen, finger, pinch, and release together.
- Ink cannot land outside a page. On pen-up, the parts of the stroke outside
  its page are removed (Noteful's behavior); a stroke entirely outside is
  removed.

## Visual style

Both hosts use complete iOS-style controls: SwiftUI and UIKit on the iPad,
Flutter Cupertino on the web. Their behavior belongs to the
components identified in [ARCHITECTURE.md](../ARCHITECTURE.md#component-ownership).
Apply the colors below through each framework's theme. Math Notes supplies
product layout and theme values.

Dark theme: the toolbar, bars, menus, popovers, and library panels are dark
navy and dark gray, so the page stands apart from the controls. One blue
accent (#2F6FEB, approximately) for primary buttons, selection and links.
Rounded cards and chips, system sans-serif type. Paper is warm off-white.

## Relation to the current model

| Mockup | Current model ([FORMAT.md](../FORMAT.md), [FEATURES.md](../FEATURES.md)) |
| --- | --- |
| Paper Style, Starting Template (backgrounds) | Built-in templates: blank, lined-*, grid-*, dotted (#21) |
| Pen, highlighter, saved pens, color palette | Tool settings and saved pens in `.pens.json` (#25); Google Ink brush geometry in the current engine |
| Eraser, Lasso, Drawing mode | #23, #24, [TikZ drawing mode](tikz-drawing-mode.md) |
| Undo and redo, page overview | #22, #21 |
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
