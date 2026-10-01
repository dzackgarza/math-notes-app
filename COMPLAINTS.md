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
