# Complaints

Open usability defects in the deployed web app. Each entry states the defect and the required state.
Delete an entry when the deployed app has the required state.

## Editor

- **The Pen popup merges two tools.** The Pen popup also sets the highlighter. A marker is not a pen. Required: Pen and
  Marker are separate tools, each with its own popup.
- **The tool bar is a docked sidebar.** The tools sit in a column on a dark strip at the left edge of the page.
  Required: a floating ribbon over the page.
- **Opening a note is unreliable.** A tap on a note sometimes does nothing, and sometimes the note opens after 10 s or
  more. Required: one tap opens the note at once.
- **Errors are silent.** A failed action shows no message and writes no log. Required: each failure shows a toast and
  writes to the browser console.
