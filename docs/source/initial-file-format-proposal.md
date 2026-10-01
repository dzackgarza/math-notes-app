# Initial file-format proposal

Source record: an early design proposal supplied for comparison. The text
below is retained as given. The current format contract is
[FORMAT.md](../FORMAT.md); later decisions may refine this proposal.

---

Yes. I would make this a foundational constraint:

> The authoritative state is a normal directory tree containing documented, standards-based files. The app owns no private library format and performs no proprietary “sync.”

Write gets this direction largely right, although its current `.svgz` choice is not ideal for a successor. Stylus Labs itself notes that `.svgz` is gzip-compressed SVG, can be decompressed to ordinary SVG, and has uneven browser support; Chrome dropped direct SVGZ support years ago. ([Stylus Labs][1])

For the new app, I would use plain SVG and ordinary directories.

A notebook root could look like this:

```text
Notes/
├── Algebraic Geometry/
│   ├── stable-pairs/
│   │   ├── notebook.json
│   │   ├── pages/
│   │   │   ├── 0001.svg
│   │   │   ├── 0002.svg
│   │   │   └── 0003.svg
│   │   ├── assets/
│   │   │   ├── paper.pdf
│   │   │   └── diagram.png
│   │   └── attachments/
│   └── MMP/
│       └── ...
└── scratch/
    └── ...
```

`notebook.json` should be deliberately boring:

```json
{
  "format": "open-notebook",
  "version": 1,
  "title": "Stable pairs",
  "pages": [
    "pages/0001.svg",
    "pages/0002.svg",
    "pages/0003.svg"
  ]
}
```

If the application disappeared permanently, the important content would remain:

```text
*.svg   → browser, Inkscape, Illustrator, XML tools
*.pdf   → any PDF reader
*.png   → any image viewer
*.json  → any text editor
*.m4a   → any audio player
```

No migration program should be required merely to recover the notes.

SVG is particularly appropriate because it explicitly supports application-specific round-tripping metadata. SVG 2 permits arbitrary foreign namespaced metadata and attributes; conforming renderers preserve them while ignoring them for rendering. The standard explicitly describes this as useful for authoring applications that need model-level information for round-tripping. ([W3C][2])

So an ink stroke could remain completely valid SVG:

```xml
<path
    id="stroke-018fd2..."
    d="M 10.2 50.1 C ..."
    fill="none"
    stroke="#111"
    stroke-width="2.1"
    data-ink-pressure="..."
    data-created="2026-09-25T17:43:21Z"
/>
```

Or richer non-rendering information can live under:

```xml
<metadata>
   ...
</metadata>
```

Thus Inkscape sees a path. Firefox sees a path. The notebook application sees a handwriting stroke with pressure/history/semantic information.

I would avoid making `foreignObject` essential to rendering. SVG supports it, including HTML and MathML, but interoperability is weaker than basic SVG geometry/text. ([W3C][3]) Use standard `<text>`, `<path>`, `<image>`, `<g>`, transforms, clips, etc. wherever possible.

The filesystem hierarchy itself should also be the organizational model. If the user renames:

```text
Notes/Geometry/
```

to:

```text
Notes/Research/Geometry/
```

using Dropbox, `mv`, Files.app, Nautilus, or anything else, the application should simply discover that state. There should not be an internal database asserting that the notebook is still somewhere else.

SQLite can still exist, but only as a disposable cache:

```text
Authoritative:
    SVG / JSON / assets on disk

Derived and disposable:
    thumbnails
    OCR index
    FTS database
    recently-opened list
    rendering cache
```

Deleting the database must never destroy information.

The iPad side fits this model unusually well. iOS explicitly permits the user to select an external directory, including one exposed through a third-party File Provider. The app receives a security-scoped URL to that directory and can retain a security-scoped bookmark for subsequent launches. The permission covers the directory recursively, including files subsequently created inside it. ([Apple Developer][4])

So the initial setup can literally be:

```text
Choose notebook folder
        │
        ▼
Files picker
        │
        ├── On My iPad
        ├── iCloud Drive
        ├── Dropbox
        ├── OneDrive
        └── other File Provider
        │
        ▼
/Dropbox/Notes
```

After that, the app edits those files in place.

Apple's `UIDocument` architecture is explicitly designed for coordinated reading/writing of documents backed by cloud services, including safe replacement saves and external-change/conflict handling. ([Apple Developer][5])

Dropbox exposes itself in Files on iOS and supports editing/uploading files there. ([Dropbox Help Center][6])

Thus:

```text
Apple Pencil
     ↓
app modifies pages/0007.svg
     ↓
atomic/coordinated filesystem save
     ↓
Dropbox File Provider observes change
     ↓
Dropbox uploads it
     ↓
other machine receives it
```

There is no application-level Dropbox integration in this path.

That is exactly what I would want.

The web side has one important complication.

On Chromium-based browsers, the browser application can do essentially the same thing. `showDirectoryPicker({mode: "readwrite"})` grants a web application read/write access to a user-selected filesystem directory. ([MDN Web Docs][7])

So under Linux:

```text
~/Dropbox/Notes
       ▲
       │ normal Dropbox daemon
       │
Chromium
       │
File System Access API
       │
browser notebook app
```

is a completely viable architecture.

The browser app can retain the directory handle and subsequently reopen the library, subject to browser permission rules.

However, this is not currently portable across browsers. As of September 2026, `showDirectoryPicker()` is supported by Chromium/Edge but **not Firefox or Safari**. ([Can I use][8])

That matters particularly because you are currently using Firefox on Linux.

So there should be three web storage modes:

```text
1. Direct filesystem
   Chromium
   showDirectoryPicker()
   ~/Dropbox/Notes

2. Remote filesystem
   Dropbox/WebDAV/etc. via HTTP API
   same files, remote storage

3. Local bridge
   Firefox or other restricted browser
   tiny localhost filesystem service
   browser UI talks to localhost
```

The third option need not become a “desktop app.” It can be a tiny executable with essentially one job:

```text
localhost:31415
      │
      ├── list directory
      ├── read file
      ├── atomic write
      ├── watch changes
      └── report filesystem events
```

The entire application remains a browser application. The helper merely gives Firefox a controlled portal to a directory that web security intentionally prevents it from accessing directly.

That would also permit filesystem watching, something that browser directory handles do not give particularly elegantly.

The website case can be even simpler.

Because the content consists of static web-compatible files, the same notebook directory can be hosted directly:

```text
/var/www/notes/
├── Algebraic Geometry/
│   └── stable-pairs/
│       ├── notebook.json
│       └── pages/
│           ├── 0001.svg
│           └── 0002.svg
```

A generic viewer at:

```text
https://example.org/viewer/
```

could load:

```text
https://example.org/notes/Algebraic%20Geometry/stable-pairs/notebook.json
```

and render the SVG pages.

No conversion job is intrinsically necessary.

Even without the viewer, this works:

```text
https://example.org/notes/.../pages/0002.svg
```

because it is an ordinary SVG document.

I would explicitly support that as a compatibility invariant:

> Every page must render intelligibly when opened directly in a standards-compliant browser without any notebook JavaScript.

That is a very strong longevity property.

There is another important structural decision: avoid putting an entire 400-page notebook into one XML file.

Write's single-file model is convenient, but it has poor synchronization locality. Changing one stroke potentially changes one large synchronized object.

Instead:

```text
notebook
    page 1.svg
    page 2.svg
    ...
    page 400.svg
```

means writing on page 217 causes Dropbox to synchronize approximately:

```text
pages/0217.svg
```

rather than a 100 MB notebook.

It also reduces conflict scope. Two machines can edit different pages simultaneously without touching the same file.

Assets should likewise remain independent:

```text
assets/figure.svg
assets/lecture-slides.pdf
assets/photo.jpg
```

rather than being base64-embedded unless there is a compelling reason.

One step further would make it unusually robust for ordinary filesystem sync: stable IDs everywhere.

For example:

```xml
<g id="layer-5bb0...">
    <path id="stroke-af28..." .../>
    <path id="stroke-91c3..." .../>
</g>
```

and in the manifest:

```json
{
  "pages": [
    {
      "id": "c718...",
      "file": "pages/0001.svg"
    }
  ]
}
```

Renaming/reordering then does not change object identity.

Files should also be serialized deterministically:

```text
stable element ordering
stable numeric formatting
stable attribute ordering
no random whitespace rewrites
no regenerated base64 thumbnails
```

That makes Dropbox history, git, diff tools, rsync, backups and conflict recovery vastly more useful.

One thing I would deliberately *not* do is make the primary notebook a ZIP container such as:

```text
foo.notebook
```

containing JSON/SVG internally.

ZIP is attractive because it gives one file, but it sacrifices several of the properties you care about:

* ordinary directory synchronization becomes whole-archive synchronization;
* direct web hosting no longer works;
* individual SVGs cannot simply be opened;
* git diffs become useless;
* external assets become opaque;
* partial recovery becomes harder.

An optional ZIP form is fine for:

```text
Send notebook
Archive notebook
Download notebook
```

but it should simply be a transport/archive representation of the directory.

Likewise I would not use OPFS as authoritative browser storage. OPFS is useful and widely available, but by definition it is private to a web origin and not user-visible. ([MDN Web Docs][9]) That is exactly the opposite of this requirement.

OPFS is appropriate for:

```text
thumbnail cache
compiled search index
temporary PDF render cache
WASM scratch space
```

not notes.

So the strongest formulation of the architecture would be:

```text
                     NORMAL FILESYSTEM
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
      Dropbox            git/rsync        Web server
         │                                   │
         ▼                                   ▼
  Notes/.../*.svg                    static HTTP files
         │                                   │
   ┌─────┴─────┐                             │
   │           │                             │
iPad app    Linux browser ◄──────────────────┘
   │           │
Files API   directory access / localhost bridge
   │           │
   └─────── edit same files ────────────────┘
```

There is no separate concept called “sync.”

There is only:

> **save the file at the location the user chose.**

The external filesystem provider determines what happens next.

I would elevate four rules to non-negotiable format invariants:

1. **Every page is valid standalone SVG.**
2. **Every non-SVG object is stored in a documented standard format.**
3. **The complete notebook can be reconstructed solely from its directory contents; databases and caches are disposable.**
4. **Saving edits the files in place at their existing filesystem URLs. There is no mandatory import/export or proprietary cloud library.**

That preserves the best architectural idea in Write while improving its weak points: plain `.svg` rather than `.svgz`, page-granular files rather than giant documents, deterministic serialization, standard assets, and a documented manifest.

[1]: https://styluslabs.com/faq?utm_source=chatgpt.com "FAQ"
[2]: https://www.w3.org/TR/SVG/struct.html?utm_source=chatgpt.com "Document Structure — SVG 2"
[3]: https://www.w3.org/TR/SVG/embedded.html?utm_source=chatgpt.com "Embedded Content — SVG 2"
[4]: https://developer.apple.com/documentation/uikit/providing-access-to-directories?changes=l_5&language=objc&utm_source=chatgpt.com "Providing access to directories | Apple Developer Documentation"
[5]: https://developer.apple.com/documentation/uikit/uidocument?utm_source=chatgpt.com "UIDocument | Apple Developer Documentation"
[6]: https://help.dropbox.com/integrations/ios-files-app?utm_source=chatgpt.com "Add Dropbox to the Files app on iPhone or iPad - Dropbox Help"
[7]: https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker?utm_source=chatgpt.com "Window: showDirectoryPicker() method - Web APIs | MDN"
[8]: https://caniuse.com/mdn-api_window_showdirectorypicker?utm_source=chatgpt.com "Window API: showDirectoryPicker | Can I use... Support tables for HTML5, CSS3, etc"
[9]: https://developer.mozilla.org/zh-CN/docs/Web/API/File_System_API/Origin_private_file_system?utm_source=chatgpt.com "源私有文件系统 - Web API | MDN"
