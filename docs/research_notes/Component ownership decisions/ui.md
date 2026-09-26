# UI, navigation, and file ownership decisions

Research date: 2026-09-27. The supported web host uses Solid 1.9 and Ionic 8; the native host uses UIKit and SwiftUI. The on-disk contract is an ordinary user-selected directory with independent page SVG files and figure assets ([architecture](../../ARCHITECTURE.md), [format](../../FORMAT.md)). Package versions below are selection pins for the plans, not claims that they are installed.

## Which components own scrolling, zoom, and page-end insertion?

### Takeaway

Select browser-native scrolling in Framework7 `page-content` for the editor viewport and `UIScrollView` for iPad. Framework7 9.1.2 and MJRefresh 3.7.9 own the respective bottom-pull interaction; the application gates their release callback by a short held-ready interval before issuing the notebook add-page command. Select `@use-gesture/vanilla` 10.3.1 for web pinch recognition. On the web, keep the canvas at `touch-action: auto` and adopt Chromium PDF viewer's tested pointer/touch event arbitration as a narrow input adapter: pen draws; finger contact starts the browser's native scroll. No application code computes pan velocity, resistance, or bounce.

### Cited Findings

- Framework7 9.1.2 documents `ptr-bottom`, a threshold, progress events, and `ptr:refresh` on release. Its Core API accepts a specified app root (`el`), so the editor can have one Framework7 `page-content` scroll container inside its own root while Solid renders its children and the existing Ionic controls remain outside that viewport. The selected boundary is the editor viewport only; Ionic `IonContent` does not scroll that same viewport. — [Framework7 pull-to-refresh](https://framework7.io/docs/pull-to-refresh.html), [Framework7 app root](https://framework7.io/docs/app), [Framework7 app layout](https://framework7.io/docs/app-layout.html)
- Framework7's page content uses browser `overflow: auto` and `-webkit-overflow-scrolling: touch`. Its bottom-pull component owns its resistance, translation, state, and release event. It requires a `.page` ancestor and a Framework7 app instance; it is not a standalone module that can be attached to an Ionic scroll element. Its public `pullMove` event reports `touchesDiff` and `translate`, and `refresh` supplies a `done` callback. — [Framework7 page CSS](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/page/page.less), [scroll mixin](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/less/mixins.less), [PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js)
- Framework7's release event is distance-based; its documented options do not include a hold duration. The bounded application rule records when the framework reports ready pull state and accepts the release callback only if it remained ready for the specified interval. On a shorter pull it calls the framework's `done` callback. The component retains all motion and state transitions. — [Framework7 PTR API and events](https://framework7.io/docs/pull-to-refresh.html), [PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js)
- MJRefresh's `MJRefreshBackFooter` on `UIScrollView` changes to `MJRefreshStatePulling` while a finger remains down and calls `beginRefreshing` after release. Its public component exposes `state`, `pullingPercent`, a callback, and `endRefreshing`. Select the back footer, not the auto footer, with the same narrow elapsed-ready command gate. MJRefresh has MIT license, Swift Package Manager support, and tag 3.7.9. — [MJRefresh project](https://github.com/CoderMJLee/MJRefresh/tree/3.7.9), [back-footer source](https://github.com/CoderMJLee/MJRefresh/blob/3.7.9/MJRefresh/Base/MJRefreshBackFooter.m), [component API](https://github.com/CoderMJLee/MJRefresh/blob/3.7.9/MJRefresh/Base/MJRefreshComponent.h)
- `UIScrollView` provides the native iPad scroll and zoom host. `@use-gesture/vanilla` provides web `PinchGesture` for touch and trackpad recognition, with start/update/end events; the notebook viewport converts recognized scale and focal point to its renderer view. The package version is 10.3.1 under MIT. — [UIKit scroll view](https://developer.apple.com/documentation/uikit/uiscrollview), [gesture API](https://use-gesture.netlify.app/docs/gestures/), [package](https://www.npmjs.com/package/@use-gesture/vanilla)
- Ionic `ion-refresher` is a top pull-down component. Ionic `ion-infinite-scroll` fires when scrolling reaches a bottom threshold, before release. Neither is the selected page-end action. — [Ionic refresher](https://ionicframework.com/docs/api/refresher), [Ionic infinite scroll](https://ionicframework.com/docs/api/infinite-scroll)
- Web `touch-action` is set before a pointer listener runs; changing it after gesture start has no effect. The existing canvas-wide `touch-action: none` blocks browser panning from a finger on that canvas. It must become `auto` on the ordinary page surface. — [Pointer Events standard](https://www.w3.org/TR/pointerevents/), [MDN touch-action](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/touch-action)
- Chromium's PDF ink host is a mature browser reference for the exact input split. It observes `pointerdown` first, records the pointer type and event timestamp, then calls `preventDefault()` on the matching `touchstart` only when that pointer should ink. Once a pen has been used, finger touch is allowed to start a pan anywhere on the page. Chromium's own tests assert that in-page pen prevents default while in-page finger starts a gesture in pen mode. This is an event-routing reference, not a framework for drawing or scrolling; Math Notes must connect the resulting pen samples to its document ink engine. — [Chromium PDF ink host](https://chromium.googlesource.com/chromium/src/+/be0366525a33fc4df00ab2b4164cb0f506dcc47b/chrome/browser/resources/pdf/elements/viewer-ink-host.ts), [Chromium gesture tests](https://chromium.googlesource.com/chromium/src/+/fcbdc2a473cb996c9e6b9382631ae8930924a22a/chrome/test/data/pdf/annotations_feature_enabled_test.ts)
- The Touch Events standard allows cancellation of `touchstart` to prevent default scrolling. iOS WebKit also exposes `Touch.touchType` to identify a stylus, but browser compatibility data does not show that property across Chromium and Firefox; it is an iOS-specific route, not a cross-browser substitute for the Chromium reference. — [Touch Events standard](https://www.w3.org/TR/touch-events/), [Touch.touchType](https://developer.mozilla.org/en-US/docs/Web/API/Touch/touchType), [browser compatibility record](https://github.com/mdn/browser-compat-data/blob/main/api/Touch.json)
- Wacom's Digital Ink Web `InputListener` can be configured for pen input, but its documented pointer-type filter does not claim ownership of browser scrolling, bottom pull, or pinch arbitration. MyScript iink is a larger editor with documented pen-write/finger-manipulate behavior; its editor and cloud/service document contract would replace more than the scroll subsystem and does not establish the required local standalone SVG page ownership. Neither is selected as the scroll owner. — [Wacom InputListener](https://developer-docs.wacom.com/docs/sdk-for-ink/api/digital-ink-web/InputListener/), [MyScript interactive ink](https://developer.myscript.com/doc/interactive-ink/4.0/concepts/interactive-ink/)

### Inferences

- The Framework7 app root can be a nested editor workspace because its `el` API supports an app root other than `body`; one owner must control the actual scrollable element. This is a source-based integration choice, not yet a measured cross-framework rendering result.
- The app-specific hold rule is a command acceptance rule after a complete framework pull action. It is not an alternative touch controller.

### Gaps

- The selected source establishes the browser event-routing pattern, but the current Math Notes canvas has not implemented it. A real iPadOS WebKit and supported desktop Chromium pen device must show pen stroke continuity, finger native fling/bounce, two-finger zoom, and page-end pull together before acceptance. This is an integration proof of the selected architecture, not a later dependency-selection task. Chromium warns that non-passive touch listeners can delay the start of scrolling; attach the arbitration listener only to the canvas contact surface, not the document or scroll viewport, and measure the device result. — [Chrome scrolling intervention](https://developer.chrome.com/blog/scrolling-intervention), [Chromium ink host](https://chromium.googlesource.com/chromium/src/+/be0366525a33fc4df00ab2b4164cb0f506dcc47b/chrome/browser/resources/pdf/elements/viewer-ink-host.ts)
- Framework7's pull source tracks one touch identifier and has no documented pinch-arbitration contract. Its `.ptr-ignore` escape hatch would also suppress page-end pull on the ignored area. The selected pinch recognizer and bottom pull therefore need an explicit combined device demonstration before the editor interaction is accepted. — [Framework7 PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js), [Framework7 PTR docs](https://framework7.io/docs/pull-to-refresh.html)
- Framework7 9.1.2 docs/source establish bottom pull and release, but not a built-in hold-to-arm timer. The narrow timer rule is a product extension of the selected component. Its exact duration is a product tuning value; it does not define or replace motion physics.
- Framework7's web bottom pull requires touch input; its source attaches mouse-wheel handling only when `ptr.bottom` is false. Desktop users retain the visible add-page command. — [Framework7 PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js)

## Which components own tabs and split panes?

### Takeaway

Select Kobalte Tabs 0.13.14 for document tabs and `@corvu/resizable` 0.2.5 for resizable web panes. Ionic owns the library sidebar's responsive show/hide behavior; UIKit/SwiftUI own native panes and tabs.

### Cited Findings

- Kobalte Tabs implements the WAI-ARIA tabs pattern, linked panels, focus management, LTR/RTL keyboard behavior, dynamic tab lists, and controlled selection. Version 0.13.14 declares Solid `^1.9.8` compatibility and MIT license. Math Notes supplies tab IDs, note state, open/close commands, and Ionic theme styling. — [Kobalte tabs](https://kobalte.dev/docs/core/components/tabs/), [package metadata](https://www.npmjs.com/package/@kobalte/core)
- corvu's Resizable provides horizontal/vertical panels, pointer and keyboard handles, collapse, size callbacks, and WAI-ARIA separator semantics. Version 0.2.5 declares Solid `^1.8` compatibility and MIT license. The host stores pane proportions; document position is separate. — [corvu Resizable](https://corvu.dev/docs/primitives/resizable/), [package metadata](https://www.npmjs.com/package/@corvu/resizable)
- Ionic `ion-split-pane` shows or hides side content based on responsive breakpoints and is already used for the library. It has no documented resize-handle API in the inspected component contract, so corvu owns any draggable splitter. — [Ionic split pane](https://ionicframework.com/docs/api/split-pane)

### Inferences

- A document tab is identified by a durable note ID. Kobalte supplies tab behavior; the application attaches close and add controls without replacing keyboard navigation.

### Gaps

- The proposed theme composition of Kobalte and Ionic requires rendered device inspection. No source claims a prebuilt Ionic skin for Kobalte.

## Which components own object manipulation, text, and transfer?

### Takeaway

Select interact.js 1.10.28 for touch-capable web object manipulation handles and the fork of Stylus Labs Write at `401b65d5fe0294cc83171b76a0273b6df3afc979` for native selected-object resize and rotation handles. UIKit drag-and-drop owns native external transfers; native editing controls own text entry; Skia Paragraph owns shared rendered text layout. Forked Write's `Selection` and document command/undo path own selection membership and committed SVG transforms across hosts.

### Cited Findings

- interact.js supplies browser drag, resize, multitouch gesture, snapping, restriction, dropzones, and inertia. Its draggable/resizable APIs expose start/move/end deltas and rectangles. Version 1.10.28 is MIT. Attach it only to selected object overlays or handles, leaving the page's ordinary scroll surface to the scroll owner. — [interact.js project](https://github.com/taye/interact.js), [dragging](https://interactjs.io/docs/draggable/), [resizing](https://interactjs.io/docs/resizable/), [dropzones](https://interactjs.io/docs/dropzone/), [package metadata](https://www.npmjs.com/package/interactjs)
- Interact.js's own docs require `touch-action: none` on drag targets; applying it to selection handles preserves a separate ordinary page scroll target. The engine receives the completed transform in document coordinates. — [interact.js dragging](https://interactjs.io/docs/draggable/), [resizing](https://interactjs.io/docs/resizable/)
- Write already implements the complete native selection-handle interaction in C++ rather than delegating it to UIKit: `RectSelector::drawBG` paints the resize corners and rotation handle; `scaleHandleHit` and `rotHandleHit` enlarge hit regions for touch and return the transform origin; `ScribbleArea::selectionHit` chooses the action; the move/release path calls `Selection::scale`, `rotate`, and `commitTransform`. Use these functions together from the Write fork for selected page objects and render their visual affordance through the fork's painter. The iPad host forwards only input that begins on an active handle to this subsystem; `UIScrollView` retains ordinary page panning and zoom. Math Notes adapts selected SVG element IDs and committed transforms at the existing C++ document boundary, not a second UIKit handle geometry implementation. The inspected upstream source is AGPL-3.0. — [Write selection interface](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/selection.h), [handle hit and painting](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/selection.cpp), [ScribbleArea action flow](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribblearea.cpp), [Write license](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/LICENSE)
- Konva's Transformer supplies canvas object resize/rotate, but Konva owns a separate 2D scene and canvas. Its own guide says a production editor still needs text editing, export, templates, and other editor behavior; its gesture guide says only basic touch events are built in. It is therefore a candidate for replacing a whole web editor, not a handle overlay on the current Skia canvas. — [Konva Transformer](https://konvajs.org/docs/select_and_transform/Basic_demo.html), [Konva production-editor note](https://konvajs.org/docs/react/Transformer.html), [Konva gesture guide](https://konvajs.org/docs/sandbox/Gestures.html)
- tldraw is a complete React infinite-canvas editor SDK, with shape and SVG export extension points. It was considered as a whole web editor, but its documented React and infinite-canvas model does not directly supply the native UIKit host or fixed-page SVG document contract. This is an integration cost, not proof of impossibility. — [tldraw SDK](https://tldraw.dev/), [custom SVG export](https://tldraw.dev/sdk-features/image-export)
- Ionic `ion-textarea` uses a native textarea for entry, composition, caret, and selection; UIKit `UITextView` provides native text editing on iPad. Skia Paragraph lays out and shapes text to a width before rendering in the engine. Math Notes stores authored text and maps the resulting baselines to SVG `<text>/<tspan>`. — [Ionic textarea](https://ionicframework.com/docs/api/textarea), [UIKit UITextView](https://developer.apple.com/documentation/uikit/uitextview), [Skia Paragraph](https://skia.org/docs/user/modules/quickstart/)
- UIKit's drag-and-drop interactions and `NSItemProvider` own native external transfers. Math Notes maps accepted data to page assets and document commands. — [UIKit drag and drop](https://developer.apple.com/documentation/uikit/drag-and-drop)

### Inferences

- interact.js is the web interaction owner for selected overlay handles. Forked Write is the corresponding native handle owner, including paint, hit target, and transform session. Forked Write `Selection` owns membership and committed SVG transforms; web interact.js forwards its completed session to that same document authority. UIKit drag-and-drop owns only transfers between views or applications, not resizing or rotation.

### Gaps

- The inspected APIs do not prove that interact.js handles perform the complete application's selection semantics or coexist with pen capture without input arbitration. The selected boundary is handles and drag/drop sessions, not selection inference.
- Write's handle methods operate on Write `Selection`, `Element`, `Page`, `Painter`, and `ScribbleArea` types, not an isolated UIKit control. The fork must host that connected subsystem and bridge its selection/commit boundary to the Math Notes document model. Copying only the hit-test formulas into Swift would recreate the interaction and is not the selected integration. The AGPL license must remain valid for the forked app distribution.
- Browser text entry and Skia's rendered paragraph can use different font shaping environments. A font/metrics contract is needed for exact editable SVG fidelity; the selected Skia layout avoids a separate handwritten line-layout algorithm.

## Which APIs own folder persistence and document lifecycle?

### Takeaway

Select the browser File System Access API for per-file writes and IndexedDB/idb-keyval for the retained directory handle. Select a `UIDocumentPickerViewController` security-scoped folder with `NSFileCoordinator` per changed file and a root `NSFilePresenter` on iPad. The application's save adapter owns only the list of changed paths and conflict decisions required by its ordinary-directory format.

### Cited Findings

- The format requires every changed page to replace only its own standalone SVG in the selected directory. `FileSystemFileHandle.createWritable()` does not expose changes until its stream closes and typically stages a replacement file; the browser must await write and close before acknowledging save. The folder picker returns a directory handle for local files. — [Math Notes format](../../FORMAT.md), [createWritable](https://developer.mozilla.org/en-US/docs/Web/API/FileSystemFileHandle/createWritable), [showDirectoryPicker](https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker)
- Apple documents selecting a folder from iCloud Drive or third-party File Providers with `UIDocumentPickerViewController`; the returned security-scoped URL grants recursive folder access. Apple requires file coordination for reads and writes under that URL. `NSFileCoordinator` coordinates individual files and directories with file presenters. — [Apple directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories), [file coordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- `UIDocument` offers autosave, file coordination, conflict notifications, and `FileWrapper` directory packages. Its documented save boundary is one document file or package, and the inspected docs do not establish the required independent dirty-page writes in ordinary nested directories. It is not the selected owner for this format. — [UIDocument](https://developer.apple.com/documentation/uikit/uidocument), [FileDocument packages](https://developer.apple.com/documentation/swiftui/filedocument)
- The web app already uses idb-keyval to retain a directory handle, and the native plan already uses folder bookmarks, `NSFileCoordinator`, and `NSFilePresenter`. — [web package](../../../hosts/web/package.json), [Math Notes architecture](../../ARCHITECTURE.md)

### Inferences

- A notebook's file map and dirty-path set are product data; the browser and Apple APIs own the actual per-file operations and platform coordination. A multi-file notebook update may need a format-specific commit order because neither platform API provides one atomic transaction over the entire directory.

### Gaps

- The inspected browser API guarantees visibility after `close()` for a file, not an atomic transaction over several SVG, JSON, and TikZ files. The save protocol must state and preserve recovery behavior for interrupted multi-file updates.
- The selected iPad APIs provide coordination, but conflict resolution policy for two writers editing the same page is a notebook rule. Source-preserving conflict handling needs a concrete decision in the format contract.

## Search record

### Takeaway

The choices above follow the complete-component and platform-API survey below; they are selections for the implementation plan rather than deferred dependency research.

### Cited Findings

- Official API and source pages used for the decision are linked in each section. Current package versions and license fields came from the packages' public registry records. — [npm registry API](https://registry.npmjs.org/), [Framework7 source tag](https://github.com/framework7io/framework7/tree/v9.1.2), [MJRefresh tag](https://github.com/CoderMJLee/MJRefresh/tree/3.7.9)

### Inferences

- Search included whole app frameworks and editor SDKs, not only small gesture packages. The selected web editor viewport still requires cross-framework composition, but that integration is bounded to one scroll owner.

### Gaps

- Live compatibility on iPadOS Safari and Chromium pen hardware has not been established from source alone.

Exact search queries:

```text
site:ionicframework.com/docs/api/content getScrollElement scroll events scrollY
site:ionicframework.com/docs/api/refresher pullMin bottom
site:ionicframework.com/docs/api/infinite-scroll position bottom threshold release
bottom pull to refresh release hold library web ionic iOS
pull up refresh bottom release hold javascript component
site:framework7.io/docs pull to refresh bottom release
site:framework7.io/docs/app root el nested app Framework7 core page
site:github.com/CoderMJLee/MJRefresh MJRefreshBackFooter release UIScrollView
site:kobalte.dev/docs/core/components/tabs Solid tabs keyboard accessible
corvu resizable SolidJS documentation resizable panels
site:interactjs.io/docs draggable resizable touch inertia dropzone
site:tldraw.dev SDK React infinite canvas SVG export
site:konvajs.org/docs selection transformer gestures touch
site:github.com/styluslabs/Write syncscribble selection RectSelector scaleHandleHit rotHandleHit
site:github.com/styluslabs/Write syncscribble ScribbleArea selectionHit MODEMOD_SCALESEL
site:skia.org/docs paragraph shaping layout
site:developer.apple.com UIDocument FileWrapper package folder external file provider
site:developer.apple.com providing access to directories file coordinator
site:developer.mozilla.org FileSystemFileHandle createWritable close
site:w3.org/TR/pointerevents touch-action pen direct manipulation
Chrome stylus pen pointer events also touch events touchstart
site:chromium.googlesource.com/chromium/src chrome pdf ink touchstart preventDefault pointerType pen pan
site:developer.myscript.com interactive ink pen finger scroll zoom web offline
site:developer-docs.wacom.com InputListener attach pointerTypes pen touch
```
