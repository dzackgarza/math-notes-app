# Visual direction

A design plan made with the `frontend-design` skill
(`anthropics/claude-code`, `plugins/frontend-design`) and the Frontend
Aesthetics cookbook it links. It replaces the theme in
[tablet-ui.md](../specs/tablet-ui.md) ("Visual style"), whose Inter face,
navy ramp, and decorative blue are the defaults that the skill names.

## Brief

| Axis | Statement |
| --- | --- |
| Subject | Handwritten research mathematics: proofs, computations, and diagrams written with a pen on ruled, dotted, or squared paper |
| Audience | One research mathematician, in long sessions with a pen in hand, on an iPad and in Chrome on Linux |
| Primary job | Write on the page; find a notebook again |
| The memorable element | The page and the ink. Notebook covers show their first handwritten page. Chrome is quiet and stays out of the page's way |
| Vernacular | Cloth-bound journal volumes and their spine labels, quad-ruled pads, blue-black fountain-pen ink, the red ribbon bookmark, chalk on slate, drafting film |

## Three directions

### A. Bound volumes (recommended)

The library is a shelf of cloth-bound volumes; the editor is an open volume
on a reading desk.

| Token | Hex | Role |
| --- | --- | --- |
| board | `#DADDD5` | Desk and chrome: binder's board, a cool gray-green |
| leaf | `#EEF0EA` | Sheets, menus, popovers |
| ink | `#1C2430` | Text and icons: blue-black ink |
| graphite | `#555D67` | Secondary text; 4.9:1 on board |
| ribbon | `#9E2A2B` | The current selection only: active tool, selected row, current page |
| paper | `#FBFAF6` | The page |

Covers use real buckram colors (navy `#24324A`, oxblood `#5B2328`, forest
`#2F4A3A`, ochre `#A87B2C`) with the title on a printed spine label.

Type: Alegreya Sans for the interface, a humanist sans with calligraphic
origins that sits beside handwriting; Alegreya, its serif partner, only for
the titles on spine labels and the library heading. Scale on a 1.333 ratio:
14 / 18 / 24 / 32, with 16 for secondary lines in rows and menus; weights
400 and 800.

```
+--------------------------------------------------------------+
| Library                                    [search]   + New  |  board
|                                                              |
|  +------+ +------+ +------+ +------+                         |
|  |~~ink~| |~~ink~| |~~ink~| |~~ink~|   first page, on cloth  |
|  |~~~~~~| |~~~~~~| |~~~~~~| |~~~~~~|                         |
|  |[Alg. | |[Latt.| |[Lect.| |[Semi.|   spine label, serif    |
|  +------+ +------+ +------+ +------+                         |
+--------------------------------------------------------------+

+--------------------------------------------------------------+
| < Algebraic Geometry      Sheaves              Pages View ...|  board
| +--+  +----------------------------------------------------+ |
| |pn|  |                                                    | |
| |mk|  |              paper, the only bright object         | |
| |er|  |                                                    | |
| |--|  |                                                    | |
| |T |  |                                                    | |
| |()|  +----------------------------------------------------+ |
| +--+  floating rail on leaf, ribbon marks the active tool    |
+--------------------------------------------------------------+
```

Principles: one accent, used only for "this one"; menus are leaf with hairline
group rules, no bands; labels are left aligned; nothing on the chrome is
brighter than the page.

### B. Seminar room

Dark slate chrome with chalk, the page the only light object.

| Token | Hex | Role |
| --- | --- | --- |
| slate | `#26302C` | Desk and chrome |
| slate-raised | `#323D38` | Sheets, menus, popovers |
| chalk | `#E9E6DA` | Text and icons |
| dust | `#A7AA9F` | Secondary text |
| chalk-yellow | `#E8C547` | The current selection only |
| paper | `#FBFAF6` | The page |

Type: IBM Plex Sans, weights 300 and 700.

### C. Drafting table

Pale engineering-pad green chrome with graphite and drafting-film blue.

| Token | Hex | Role |
| --- | --- | --- |
| pad | `#E3EBDD` | Desk and chrome, with a faint 5 mm grid |
| film | `#F3F6F0` | Sheets, menus, popovers |
| graphite | `#2E3436` | Text and icons |
| lead | `#6B7470` | Secondary text |
| drafting-blue | `#1F5FA8` | The current selection only |
| paper | `#FBFAF6` | The page |

Type: IBM Plex Sans with Plex Mono for page numbers.

## Review against the generated-design tells

| Tell (frontend-design, "Process") | A | B | C |
| --- | --- | --- | --- |
| 1. Cream background, serif display, terracotta accent | Clear: gray-green board, serif only on spine labels, crimson ribbon | Clear | Clear |
| 2. Near-black background with one bright accent | Clear | **At risk**: slate is dark and chalk-yellow is bright | Clear |
| 3. Broadsheet hairlines, zero radius | Clear | Clear | At risk: grid and hairlines |
| 4. SaaS-card kit: identical rounded cards, one soft shadow | Clear: covers are volumes with spine labels, not cards | Clear | Clear |
| 5. Template chrome: all-caps eyebrows, monospace data labels | Clear | Clear | **At risk**: monospace page numbers |
| Cookbook: Inter, Roboto, system fonts | Clear | IBM Plex is a common choice | IBM Plex is a common choice |
| Cookbook: a blue accent as the generic default | Clear | Clear | **At risk** |

A is the one direction grounded in the subject's own objects (the volume,
the spine label, the ribbon) with no tell at risk.

## After the choice

1. Replace the theme in `lib/ui/theme.dart` and the typography roles with the
   chosen tokens and bundled faces; rewrite "Visual style" in tablet-ui.md.
2. Rebuild, screen by screen: library and covers, creation sheets, editor
   chrome and rail, menus, popovers, page overview.
3. Each screen is done when its screenshot, read beside this plan, shows no
   default the plan did not choose. Contrast and pixel assertions guard
   regressions; they do not close a screen.
