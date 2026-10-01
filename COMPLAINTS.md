# COMPLAINTS.md

Yes. The causes are structural, not spot defects. Screenshots are in the scratchpad (`/tmp/claude-1000/-home-dzack-gitclones-math-notes-app/c1d7e838-14cb-4c16-9778-fc216174b8f1/scratchpad/0*.png`), taken from the deployment at iPad landscape (1366×1024) and portrait.

## 1. The UI font is Roboto wearing SF Pro's metrics

`CupertinoThemeData` is used with no text theme, so every label requests `CupertinoSystemText` (`.SF Pro Text`). The bundle ships no such font; CanvasKit resolves it to Roboto (65 references in `main.dart.js`). Cupertino's text styles carry SF Pro's negative tracking (−0.41 at 17 pt, tighter for bold titles). Applied to Roboto Bold, the letters collide: see "Algebraic Geometry" in `crop-title.png` and "Notebooks", "Niemeier lattices", "New Notebook". This one mismatch makes every screen read as "web page", because Roboto with cramped tracking is what a default Flutter web app looks like. The Noteful reference is SF Pro at generous size.

Fix direction: bundle one UI family designed for this role (Inter is the usual SF-compatible choice) and set a `CupertinoTextThemeData` with `letterSpacing: 0`.

## 2. Two neutral palettes on every screen

`theme.dart` defines navy chrome (`#151B2B`, `#1E2638`) and overrides four theme colors. Every surface the theme does not name comes from Flutter's dark Cupertino defaults, which are warm grays: the creation sheets (`#1E1E1E`), the menus (`#3A3A3A`), the page-overview sheet and Insert-text dialog (`#333`), and pitch-black `#000` text fields. So a sheet, menu, or dialog is always a different gray family from the app behind it (`02`, `12`, `15`, `17`). AAA apps have one neutral ramp.

## 3. No depth model

Nothing is elevated by shadow or blur. The modal dim is flat 50% gray with no blur (`15`, `17`). Menus are opaque `#3A3A3A` lists with hard 1 px full-width dividers and thick dark bands as section gaps, not the translucent grouped pull-down menus iOS users expect (`12`, `13`, `14`). The paper in the editor fills the viewport edge to edge with no page edge, margin, or shadow, so it reads as a background texture rather than a sheet (`08`). The notebook cover is a flat pastel rectangle with the title typed on it: no spine, thumbnail, or edge (`20`).

## 4. Type scale and sizes

| Measure | Value |
| --- | --- |
| Distinct `fontSize` values in `lib/` | 8 (12, 13, 14, 16, 18, 20, 22, default) |
| Uses of 12 px | 9 |

12 px appears on the sidebar "Tags" header, card metadata ("Modified 2026-10-01 14:47", a raw ISO timestamp), the helper line "You can move this notebook later.", the popover "Size" label and its five chip labels, and the "Page 1 of 1" menu header. Five-segment controls carry 12 px labels in 400 px ("Dot Paper | Grid Paper | Lined Paper | Plain Paper | Graph Paper", `06`). Noteful's popover uses one size, ~20 px.

## 5. Editor chrome stacks three bars

Tab strip (`#1E2638`), nav bar (darker), then a 740 px floating pill 15 px below it: about 160 px of chrome before the page, and the pill covers the first writing row (`08`). The pill holds 18 controls, including five saturated primary swatches (black, blue, red, green, yellow) beside the blue accent, so the toolbar is the most colorful object on screen. The single tab is a blue-tinted block with an "×", a browser-tab idiom, and the "+" sits alone at the far right. "Saved" is a bare text label among icons. Noteful uses one vertical rail, one accent, and one current-color dot.

## 6. Color used as decoration instead of state

Every sidebar row is accent blue, so the selected row (gray fill) and the four unselected rows (blue text) compete (`01`). iOS sidebars use label color for rows and the accent only for selection. "Math Notes" in the sidebar and "Notebooks" in the nav bar are two titles for one screen.

## 7. Layout residue in the sheets

The creation sheets are 900×800 with the right column ending at a "Notebook Details" block that repeats the form; the lower right quarter is empty (`02`, `06`). "Save as template" is gray text under a borderless "Settings name" field. The page-overview sheet is a near-full-screen `#333` box holding one thumbnail with a 2 px bright-blue border (`15`).

Item 1 and item 2 are each one change in `theme.dart`/`main.dart` and remove most of the "unpolished" impression; items 3 to 7 are per-screen work. Say which you want and I will start.

# Menu organization

Yes, and it is visible in the three menu screenshots alone.

**The three menus are not three categories.** The nav bar offers three unlabeled icons (grid, split, ellipsis). Opening them shows the same kinds of items in all three:

| Item | Where it is | Where the user looks |
| --- | --- | --- |
| Page overview, Previous page, Next page, Add page, Insert page before/after | Pages | Pages |
| Go to page, Select page, Clear page, Delete page, Paper for new pages | ⋯ | Pages |
| Fit width, Vertical/Horizontal scroll, Two pages | View | View |
| Toolbar at top/bottom, Hide tab bar, Split view | View | Settings or ⋯ |
| Bookmarks, Add bookmark, Layers | Pages | nowhere else, fine |
| Save, Share, Export PDF | ⋯ | document actions, fine |
| Draw with finger, Customize toolbar | ⋯ | Settings |
| Paste, Clippings | ⋯ | the selection / long-press on the page |
| Compare versions, Follow links | ⋯ | unknown; the names describe no visible object |

So "page" operations are split across two menus by no rule; "⋯" is a 15-item junk drawer holding document actions, destructive page actions, input settings, chrome settings, clipboard, and two mystery items; "View" mixes how the page is laid out with where the chrome sits.

**Within a menu there is no hierarchy.** Every item is the same 44 px row in the same white 16 px text. Separators are thick dark bands, so a group gap and a single divider look alike. "Delete page" is red but sits between "Clear page" and "Draw with finger". "Previous page" and "Next page" are disabled gray and still take two rows of a menu, for an action that is a swipe. "Layers" has a second line "Ink" in 12 px gray, the only two-line item anywhere. "Page 1 of 1" is a 12 px header on one menu only.

**Actions sit in menus; settings sit in menus; navigation sits in menus.** iOS separates them: actions in a pull-down or context menu, settings in a settings sheet, navigation by gesture or a page control. Here everything that was not a tool became a menu row, which is why the ⋯ menu is as long as the screen.

**The toolbar has the same problem.** The pill holds tools (pen to lasso), inserters (text, image, insert space, drawing mode), history (undo, redo), and five colors in one strip with one divider. Two of its icons (↕ and the curve) have no obvious meaning, and nothing in the strip says which group an icon belongs to.

**The nav bar gives no entry point.** "Saved" is a status word next to three icons without labels; the user has to open all three to learn what the app can do, and then finds that the answer is "anything, anywhere".

The fix is an information architecture pass, not a reshuffle: one object model (document / page / selection / view / settings), each action lives with its object, settings leave the menus, navigation leaves the menus, and each surface gets the Cupertino component for its kind.

# Audit against ui-ux-pro-max-skill

Guidance: `nextlevelbuilder/ui-ux-pro-max-skill` at `09170ee` (2026-09-27): `SKILL.md` priority table, `references/quick-reference.md` rule IDs, `references/pro-rules.md` (app polish), `data/products.csv` rows 93 and 128, and `scripts/search.py --design-system` for "handwriting notes stylus notebook drawing tablet dark mode". Evidence: screenshots `01`–`21` at 1366×1024 and portrait. Contrast ratios are computed from screenshot pixels with the WCAG 2.2 formula (glyph core vs. most common surrounding pixel).

## What the guidance prescribes for this product

| Source | Prescription | App |
| --- | --- | --- |
| Row 128 Drawing & Sketching Canvas | Minimalism & Swiss + Dark Mode; "neutral canvas + tool panel dark" | Conforms: dark navy chrome, cream paper |
| Row 93 Notes & Writing App | Minimalism & Swiss + Flat; "clean white/cream + minimal accent"; typography-first | Conforms on paper and accent count; fails on typography (below) |
| `--design-system` output | Inter; dark neutral palette with low-alpha borders; sharp shadows if any; no pure-white surfaces | Fails on font and on the pure-white pen/marker popovers (`09`, `10`) |
| `no-emoji-icons`, `icon-style-consistent` | SVG icons, one icon family | Conforms: one outline family in the toolbar |
| `system-controls` | Native/system controls | Conforms in kind (Cupertino menus, segmented controls, sheets); fails in theming (below) |

## Violations by priority

### 1. Accessibility (CRITICAL)

| Rule | Guidance | Observed |
| --- | --- | --- |
| `color-contrast`, `color-accessible-pairs` | 4.5:1 normal text, 3:1 large and non-text | 9 of 26 sampled text pairs fail 4.5:1; 4 fail 3:1 (table below) |
| `aria-labels` | Icon-only controls need an accessible name | Conforms: the accessibility tree names every control (Pages, View, More, Pen … Insert space, Drawing mode, Edit colors) and exposes "Saved" as a status |
| `icon-context` | Icon controls expose selected/pressed state | Fails: no toolbar button carries `aria-pressed` or `aria-selected`; the active tool is a visual fill only |
| `nav-label-icon` | Nav items need icon and visible text label | Nav bar: grid, split, ellipsis with no visible labels (`08`). Toolbar: ↕ ("Insert space") and the curve ("Drawing mode") have no visible meaning (`08`) |
| `keyboard-nav` | Tab order matches visual order; full keyboard support | Library: Tab goes Library → search field → All → Sort → New Notebook → Search → Recent …, interleaving the sidebar with the top bar. Editor: only the tab strip and "Open note" have `tabindex=0`; Pages, View, More, and all 18 toolbar controls are unreachable by keyboard |
| `focus-states` | Visible focus ring | Conforms: accent-blue ring on the focused control |
| `color-not-only`, `color-not-decorative-only` | Meaning never by color alone | "Delete page" is distinguished only by red, and that red measures 1.57:1 against the menu (`12`) |
| `escape-routes`, `modal-escape` | Cancel/back in modals | Conforms: Cancel on both creation sheets (`02`, `06`) |

Measured contrast (text on surface):

| Ratio | Sample | Screenshot | Threshold |
| --- | --- | --- | --- |
| 1.57 | "Delete page" red on menu gray | 12 | 4.5 fail |
| 2.09 | "Niemeier lattices" accent blue on blue-tinted tab | 08 | 4.5 fail |
| 2.23 | "Description" and "Text" placeholders on `#000` fields | 02, 17 | 4.5 fail |
| 2.45 | "Save as template" on sheet | 06 | 4.5 fail |
| 3.31 | Accent-blue sidebar links, "Cancel", "Save as Draft" on chrome/sheet | 01, 02, 06 | 4.5 fail |
| 3.44 | "Size" label on white popover | 09 | 4.5 fail |
| 3.56 | "Ink" sublabel in Pages menu | 14 | 4.5 fail |
| 4.31 | "Page 1 of 1" header | 14 | 4.5 fail |
| 5.05–5.97 | 12 px metadata, "Tags", helper line, placeholder in search field | 01, 02, 20 | pass |
| 9.4–21 | White item text, chip labels, page counter | 08, 12, 15, 17 | pass |

The accent `#2F6FEB` fails as text on every dark surface in the app (3.31:1 on `#1E2638`, 3.31:1 on `#252629`). The guidance's `color-dark-mode` rule says dark mode uses lighter tonal variants of the brand color; the app uses the same blue for fills and for text.

### 2. Touch & Interaction (CRITICAL)

| Rule | Guidance | Observed |
| --- | --- | --- |
| `touch-target-size`, `touch-spacing` | 44×44 pt targets, 8 px between them | Toolbar pill: 48 px tall, 44 px control pitch, 38 px visible selection box (`08`). Either the hit area is 38 px (fails size) or it fills the pitch (fails spacing); both cannot pass |
| `touch-density`, `no-precision-required` | Not cramped; no precision taps | 18 controls in 740 px; five 30 px color dots at 44 px pitch |
| `safe-area-awareness` | Primary targets away from screen edges | Tab "×" and "+" sit at the viewport edges (`08`) |

### 4. Style Selection (HIGH)

| Rule | Guidance | Observed |
| --- | --- | --- |
| `platform-adaptive`, `system-controls` | iOS idioms for navigation and controls | Opaque gray menus with hard full-width dividers and thick section bands (`12`–`14`); browser-tab strip with "×" (`08`); 50% flat scrim (`15`, `17`) |
| `effects-match-style`, `elevation-consistent` | One elevation scale matching the style | No elevation scale at all: no shadow or blur on popover, menu, sheet, or paper (`03`); the only "depth" is the scrim |
| `blur-purpose` | Blur marks a dismissable background | No blur under any modal |
| `consistency`, token-driven theming (pro-rules) | One theme, semantic tokens across all surfaces | Navy chrome vs. default warm-gray sheets `#1E1E1E`/`#333`/`#3A3A3A` and `#000` fields (`02`, `12`, `15`, `17`); white popovers in a dark app (`09`, `10`) |
| `primary-action` | One primary CTA per screen; secondary subordinate | Toolbar carries five saturated swatches plus the accent; every sidebar row is accent blue (`01`) |
| `state-clarity` | Selected/disabled states distinct and on-style | Selected sidebar row is a gray fill while unselected rows are blue text, inverting the iOS convention (`01`); disabled menu items at 3.85:1 look like enabled secondary text (`14`) |

### 5. Layout & Responsive (HIGH)

| Rule | Guidance | Observed |
| --- | --- | --- |
| `visual-hierarchy` | Hierarchy by size, spacing, contrast | Menus: every item the same 44 px row and 16 px white; the only hierarchy cue is a thick dark band (`12`) |
| `fixed-element-offset` | Fixed bars reserve space for content | Floating pill covers the first writing row of the page (`08`) |
| `spacing-scale`, pro-rules "8dp rhythm" | 4/8 pt increments | Three stacked bars totalling about 160 px with a 15 px pill offset (`08`) |
| `content-priority` | Core content first | 160 px of chrome precedes the paper in landscape; worse in portrait (`21`) |
| pro-rules "Readable text measure" | Keep sheet content width predictable | 900×800 sheets with an empty lower-right quadrant (`02`, `06`) |

### 6. Typography & Color (MEDIUM)

| Rule | Guidance | Observed |
| --- | --- | --- |
| `letter-spacing` | Respect platform default tracking | SF Pro negative tracking applied to Roboto: "Algebraic Geometry", "Notebooks", "New Notebook" collide (`crop-title.png`) |
| `text-styles-system` | Platform type styles (iOS Dynamic Type roles) | 8 ad-hoc `fontSize` values; 12 px used 9 times |
| `font-scale` | One consistent scale | 12, 13, 14, 16, 18, 20, 22 with no ratio |
| `readable-font-size` | 16 px minimum body on mobile | Segmented-control labels at 12 px in a 400 px control (`06`); popover chip labels 12 px (`09`) |
| `font-pairing` | Heading and body match | UI in Roboto, note text in Noto Sans: two neutral grotesques |
| `color-semantic` | Semantic tokens, no raw hex in components | Four theme overrides; everything else is default Cupertino gray |
| `number-tabular` and "Modified 2026-10-01 14:47" | Human-readable data formatting | Raw ISO timestamp as card metadata (`20`) |
| `whitespace-balance` | Whitespace groups related items | Toolbar groups separated by one hairline; sheets group nothing |

### 8. Forms & Feedback (MEDIUM)

| Rule | Guidance | Observed |
| --- | --- | --- |
| `input-labels` | Visible label per input, not placeholder-only | The creation sheets label every field. The Insert-text field has only the placeholder "Text" (`17`). The note sheet's "Starting Template" label sits over a field whose placeholder reads "Settings name" (`06`): the label and the field describe different things |
| `confirmation-dialogs`, `undo-support` | Confirm destructive actions; allow undo | Delete page removes the page at once with no confirmation and no undo toast; the toolbar Undo does restore it (1 / 2 → 1 / 1 → 1 / 2). With a single page the item is disabled but still listed |
| `sheet-dismiss-confirm` | Confirm before discarding unsaved input | Cancel on a creation sheet with a typed title discards it with no confirmation; Escape does nothing |
| `press-feedback` | Pressed feedback within 80–150 ms | Conforms: the pressed icon dims, then takes the selected fill (`live/press-row.png`) |
| hover state (`--design-system` output: 200–250 ms hover) | Subtle hover on interactive items | No hover state on sidebar rows or toolbar buttons: hover and idle captures are pixel-identical |
| `input-helper-text` | Persistent helper text below complex inputs | Conforms where present: "You can move this notebook later.", "Use 0 for the full text width." |
| `field-grouping` | Related fields grouped | Creation sheet repeats the form as a "Notebook Details" block instead of grouping it (`02`) |
| `progressive-disclosure` | Reveal complex options progressively | Cover style, paper, and template options all shown at once on a 900×800 sheet (`02`, `06`) |
| `empty-states` | Message plus action | Library empty state is one sentence with no action (`01`) |
| `destructive-emphasis` | Red and spatially separated from primary actions | "Delete page" is red but sits between "Clear page" and "Draw with finger" (`12`) |
| `disabled-states` | Reduced opacity, non-interactive | "Previous/Next page" are disabled rows that still occupy the menu (`14`) |

### 9. Navigation Patterns (HIGH)

| Rule | Guidance | Observed |
| --- | --- | --- |
| `nav-hierarchy` | Primary vs. secondary nav clearly separated | Page operations split across Pages and ⋯; View mixes layout with chrome placement (menu table in the previous section) |
| `overflow-menu` | Overflow holds what does not fit, not everything | ⋯ is a 15-item list holding document actions, destructive page actions, input settings, chrome settings, clipboard, and two unexplained items |
| `destructive-nav-separation` | Dangerous actions spatially separated | Delete page adjacent to Draw with finger |
| `drawer-usage` | Sidebar for secondary navigation | Conforms: library sidebar holds navigation only (`01`) |
| `nav-state-active` | Current location highlighted | Conforms in the sidebar (gray fill); fails on the tab strip, where the single tab's accent text measures 2.09:1 on its own fill |
| `avoid-mixed-patterns` | Do not mix tab + sidebar + bar at one level | Editor: tab strip, nav bar, and floating pill at one level (`08`) |
| `search-accessible` | Search reachable from the top bar | Conforms: search field in the library bar (`01`) |

## Live checks

Interaction rules were measured in the deployed app with Playwright (`scratchpad/tabs.mjs`, `live.mjs`, `live2.mjs`; captures in `scratchpad/live/`): the accessibility tree, Tab traversal, pointer press, hover, Escape and Cancel on a dirty sheet, Delete page with two pages, and Undo. The results are in the tables above.

Not measurable with this setup: `dynamic-type` (Chrome has no system text-size setting that reaches Flutter), `reduced-motion` and animation timing (§7) (a CanvasKit screenshot takes about 400 ms, longer than any transition), `form-autosave`.

## Totals

| Verdict | Rules |
| --- | --- |
| Violates | 39 |
| Conforms | 13 |
| Not measurable | 4 |

Every CRITICAL-tier failure traces to four root causes: the accent used as text on dark surfaces (contrast), icon controls with no visible label and no exposed state, the editor's nav bar and toolbar left out of the keyboard focus order, and the 18-control pill (targets). The HIGH-tier style failures trace to the four-color theme override and the absent elevation scale; the navigation failures trace to the missing object model.

# Live checks

Yes. The "Not inspected" list is now measured in the deployed app and the audit is updated (`5385a7b`). The Chrome extension dropped Tab key events and reported a 940×103 viewport, so the measurements came from Playwright against the same deployment.

What the live checks changed:

| Rule | Result |
| --- | --- |
| `aria-labels` | Conforms. Every control has a name: ↕ is "Insert space", the curve is "Drawing mode", "+" is "Edit colors", "Saved" is a status role |
| `icon-context` | Fails. No tool exposes `aria-pressed`/`aria-selected`; the active tool is a fill only |
| `keyboard-nav` | Fails. Library Tab order interleaves sidebar and top bar (Library → search field → All → Sort → New Notebook → Search → Recent). In the editor only the tab strip and "Open note" have `tabindex=0`; Pages, View, More and all 18 toolbar controls are unreachable by keyboard |
| `focus-states` | Conforms: accent ring on the focused control |
| `press-feedback` | Conforms: pressed icon dims, then takes the selected fill |
| Hover state | None: hover and idle captures are pixel-identical |
| `confirmation-dialogs` / `undo-support` | Delete page deletes at once with no confirmation or toast; toolbar Undo restores it (1/2 → 1/1 → 1/2) |
| `sheet-dismiss-confirm` | Cancel discards a typed title silently; Escape does nothing |
| `input-labels` | Corrected: the creation sheets do label every field. Only the Insert-text field is placeholder-only, and the note sheet's "Starting Template" label sits over a "Settings name" field |

Still not measurable here: `dynamic-type` (no system text-size setting reaches Flutter in Chrome), `reduced-motion` and animation timing (a CanvasKit screenshot takes ~400 ms, longer than any transition), `form-autosave`.

Totals: 39 violate, 13 conform, 4 not measurable.
