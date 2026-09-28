# UI ownership

Adopted 2026-09-27: Flutter with Cupertino owns the web GUI. UIKit owns the
independent iPad GUI. The [framework decision](../../reports/Web%20interface%20framework%20selection.md)
records the survey, alternatives, source evidence, and browser integration.
The existing C++ document engine, Google Ink, Skia, and notebook format remain
shared.

## Complete framework ownership

Flutter owns controls, routing, focus, keyboard behavior, input dispatch,
scroll physics, and accessibility semantics. Use its widgets and mature
Flutter packages for standard application behavior. Package count, another
language, and a runtime dependency do not justify bespoke replacements.
Math Notes owns notebook commands, product layout, tool state, and the
mapping from accepted host input to the shared engine.

Cupertino scrollables provide bouncing scroll physics. InteractiveViewer
provides pan, pinch, bounds, and friction; it does not promise Cupertino edge
bounce. The notebook must compose supported framework behavior and prove the
complete interaction. A missing standard behavior calls for its framework or
package owner, including a supported extension or fork where necessary.

Tabs, sheets, menus, text entry, lists, selection handles, transfers, and split
panes use this same framework input and focus system. The feature issues
specify product outcomes. They must retain standard keyboard, cancellation,
and focus behavior when they compose controls.

## Renderer, pen samples, and embedded editor

Embed the existing Skia canvas in an `HtmlElementView` as a passive renderer
with `pointer-events: none`. Flutter receives notebook contact events.
A bounded browser adapter preserves original, coalesced, and predicted pen
samples, pressure, and both tilt axes for events accepted by that notebook
target. Framework targeting, cancellation, and focus apply before document
input. A dialog over the page must prevent ink through the dialog.

The TikZ editor remains an interactive iframe in its own `HtmlElementView`.
Use Flutter's documented platform-view interception for controls above it.
Dart JavaScript interop calls the existing engine bindings and browser file
APIs. The [interface decision](interfaces.md) defines byte and sample lifetime.

UIKit owns native finger navigation, Pencil targeting, controls, and input.
`UIScrollView` contains the Metal drawing surface. MJRefresh 3.7.9
`MJRefreshBackFooter` supplies native bottom pull. The held-ready release
maps to one add-page command and its template.

## Execution and acceptance

[#56](https://github.com/dzackgarza/math-notes-app/issues/56) owns the complete
Flutter web host and deployed notebook acceptance. It includes existing
library, editor, controls, folder persistence, and offline behavior. Pin the
Flutter SDK and packages in the implementation build.

On physical Chrome pen/touch hardware, verify writing, one-finger fling and
rebound, pinch, held page-end release, cancellation, and pen interaction with
open controls. Verify keyboard navigation, text composition, and focus return
across the library and editor. Verify the TikZ
iframe when #10 integrates it. These checks validate the adopted owner.

#62 owns note tabs and the picker; #28 owns split view and conflict resolution;
#61 owns text boxes; #33 owns clipping transfers. They build within Flutter.
#7 and #34 supply the corresponding native host behavior after the web product.

## Persistence

File System Access and IndexedDB/idb-keyval own browser folder access and
retained handles. A security-scoped folder, `NSFileCoordinator`, and a root
`NSFilePresenter` own native provider access. The notebook save adapter maps
dirty paths and conflict choices. The [interface decision](interfaces.md)
states per-file guarantees, multi-file save ordering, and concurrent-writer
limits.
