# Complaints

Open usability defects in the deployed web app. Each entry states the defect and the required state.
Delete an entry when the deployed app has the required state.

## Library

The library has no single object model. The same objects and actions show in many places.

- **The sidebar is a list of views.** Library, Search, Recent, Favorites, Trash, each notebook, and each tag are separate
  sidebar rows. Required: one Notebooks view. Sort, filter and search change what it shows. No sidebar of views.
- **Notebooks show three times.** A notebook is a sidebar row, a grid card, and the detail pane at the same time. Required:
  a notebook shows once, as a card in the Notebooks view.
- **Opening does not work as expected.** Tapping a notebook card only selects it. In a notebook's note list, only the
  title text opens the note; the thumbnail and the rest of the row do nothing. Required: tapping a notebook opens it, and
  tapping any part of a note opens the note.
- **There are three or more searches:** the Search view, the library search field, and "Search this notebook". Required:
  one search field in the Notebooks view.
- **"Search this notebook" cannot work.** Notes are handwriting, and the app does no OCR (see AGENTS.md). Required: no
  search inside a notebook.
- **"New Note" at the top level has no target.** A note always belongs to a notebook. Required: no top-level notes. New
  Note is an action of an open notebook only.
- **"Choose notes folder" is a sidebar row and a Settings action.** Required: the app asks for the notes folder once, at
  first start. After that, it is a Settings option only.
- **"Refresh library" exposes a state that must not occur.** The library must always match the notes folder. A manual
  refresh means that the app can show stale data. Required: no Refresh action, and no state in which the library differs
  from the folder. Changes that the app does not make (for example, a Dropbox sync) must also show without user action.
- **Sort is a segmented control.** "Name | Last modified" as a slider does not show the direction. Required: a sort menu
  with the field and the direction (newest first, oldest first).
- **Cards have no readable identity.** The card face is the first page of the first note, so a notebook looks like a
  page. The title is white text on the white card. The note count and tags are missing. Required: the title, note count,
  modified time and tags are readable on the card.
- **The screen has two titles.** "Math Notes" in the navigation bar and "Library" as the large title.
- **Unreadable and wrong text.** The detail pane's "Modified" line is dark grey on black. "1 notes" is wrong English.
