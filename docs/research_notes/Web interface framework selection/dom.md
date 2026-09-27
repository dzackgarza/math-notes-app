# Existing DOM interface and viewport alternatives

This note assesses the existing DOM host and focused viewport packages. Its retention recommendation assumed that the current GUI architecture should remain in place. The [full-framework assessment](../../reports/Web%20interface%20framework%20selection.md) selects Flutter with Cupertino controls for the web host, with only the C++ core shared with UIKit on iPad.

## Which framework should own the web shell?

### Takeaway

Ionic 8 provides the current shell's controls, while Framework7 9.1.2 owns the current editor's scroll and bottom-pull surface. Keeping them avoids a shell rewrite but retains several interface owners. The browser host and iPad host can use different GUI frameworks; their shared boundary is the C++ document and rendering engine.

### Cited Findings

- The current web app already renders library, editor toolbars, forms, sheets, menus, popovers, and responsive layout with Ionic components; the editor mounts Framework7 only for its bottom pull. A shell migration would replace working controls and their application wiring. — [App.tsx](../../../hosts/web/src/App.tsx), [Editor.tsx](../../../hosts/web/src/editor/Editor.tsx), [web host dependencies](../../../hosts/web/package.json)
- Ionic supplies the complete web component catalog and its app container owns focus, keyboard, overlay placement, and other platform behavior. — [Ionic components](https://ionicframework.com/docs/components), [Ionic app container](https://ionicframework.com/docs/api/app)
- Framework7 also supplies a full iOS style component catalog, resizable panels, and responsive breakpoints. It is a credible whole-shell alternative, but its Core page and panel model would need to replace the existing Solid/Ionic composition. Framework7's bottom pull does not require that replacement: its Core app accepts an explicit root and its PTR instance accepts a selected page-content element. — [Framework7 app](https://framework7.io/docs/app.html), [panels](https://framework7.io/docs/panel), [PTR](https://framework7.io/docs/pull-to-refresh.html)
- Ionic's refresher operates at the top. Its infinite scroll fires on proximity to the bottom. Neither supplies a held bottom pull completed on release. — [Ionic refresher](https://ionicframework.com/docs/api/refresher), [Ionic infinite scroll](https://ionicframework.com/docs/api/infinite-scroll)

### Inferences

- Keeping the working Ionic shell would avoid a large rewrite while retaining its stock UI behavior. Framework7 could own a nested editor viewport without sharing scroll control with `ion-content`. This assesses migration work, not the amount of app-owned interaction behavior after a full-framework move.

### Gaps

- No comparative device study establishes how Framework7's full shell would change the current app's controls. The current Ionic shell has observable working integration, but that fact alone does not settle the full-framework choice.

## Which complete viewport owner best fits the existing Skia canvas?

### Takeaway

Within the existing DOM host, browser-native scrolling in Framework7 `page-content`, Framework7's bottom PTR, and `@use-gesture/vanilla` 10.3.1 split viewport ownership. The browser retains wheel, keyboard, focus, and ordinary scroll behavior; Framework7 owns bottom-pull motion and release; the pinch recognizer reports scale and focal point to the Skia view. Application code must coordinate those positions and decide whether a completed pull creates a page.

### Cited Findings

- Framework7 9.1.2 uses a native `overflow: auto` page content area. Its `ptr-bottom` mode moves its preloader below content; the source handles edge detection, pull translation, threshold, visual state, release, and reset. The released `refresh` event supplies `done()`. Its public events expose pull movement and ready state. — [page CSS](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/page/page.less), [PTR docs](https://framework7.io/docs/pull-to-refresh.html), [PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js)
- Framework7 PTR has no documented hold duration. A short ready-state timer gates the resulting add-page command; it does not implement resistance or scrolling. The current editor already uses this event boundary. — [PTR docs](https://framework7.io/docs/pull-to-refresh.html), [Editor.tsx](../../../hosts/web/src/editor/Editor.tsx)
- BetterScroll 2.5.1 includes configurable momentum, bounce, bidirectional free scroll, pinch zoom, wheel input, scrollbars, and bottom pull-up. Its zoom plugin owns the scale and coordinates of a DOM content element. — [options](https://better-scroll.github.io/docs/en-US/guide/base-scroll-options.html), [zoom](https://better-scroll.github.io/docs/en-US/plugins/zoom.html), [wheel](https://better-scroll.github.io/docs/en-US/plugins/mouse-wheel.html), [scrollbar](https://better-scroll.github.io/docs/en-US/plugins/scroll-bar.html), [package](https://www.npmjs.com/package/better-scroll)
- BetterScroll's `pullingUp` event fires once the position crosses the configured bottom threshold, including before release. A positive threshold fires before the edge. Its pinned input handler uses `touchstart`/`touchmove` and mouse events, cancels default behavior by default, and does not route by `PointerEvent.pointerType`. The pinned zoom handler inspects `TouchEvent.touches`. Therefore using it here requires pen/touch arbitration plus a separate held-release rule or a maintained plugin/fork. — [pull-up docs](https://better-scroll.github.io/docs/en-US/plugins/pullup.html), [input source at v2.5.1](https://github.com/ustbhuangyi/better-scroll/blob/v2.5.1/packages/core/src/base/ActionsHandler.ts), [zoom source at v2.5.1](https://github.com/ustbhuangyi/better-scroll/blob/v2.5.1/packages/zoom/src/index.ts), [pull-up source at v2.5.1](https://github.com/ustbhuangyi/better-scroll/blob/v2.5.1/packages/pull-up/src/index.ts)
- BetterScroll documents its replacement of browser scrolling and native click behavior; `click` must be enabled to redispatch clicks. Its plugin list includes a scrollbar but no keyboard scrolling plugin. This is a stronger compatibility burden for a desktop Chrome editor than retaining the browser scroll element. — [options](https://better-scroll.github.io/docs/en-US/guide/base-scroll-options.html), [plugin list](https://better-scroll.github.io/docs/en-US/plugins/)
- OpenSeadragon has per-pointer gesture settings, pinch, pan, and flick. Its public model is an image/tile viewer, and the inspected API supplies no bottom pull action. Mapping the existing engine's live Skia surface into its viewer is a larger rendering adapter. — [OpenSeadragon API](https://openseadragon.github.io/docs/OpenSeadragon.html), [viewport API](https://openseadragon.github.io/docs/OpenSeadragon.Viewport.html)
- Pixi Viewport offers drag, pinch, wheel, deceleration, and bounce, but its input manager treats all non-mouse pointers as touch pointers and its display model depends on Pixi. It supplies no documented held bottom pull. It would add a second scene/interaction runtime around the existing Skia canvas. — [pinned input source](https://github.com/pixijs-userland/pixi-viewport/blob/v6.0.0/src/InputManager.ts), [viewport project](https://github.com/pixijs-userland/pixi-viewport)

### Inferences

- BetterScroll is the closest unified third-party viewport among the packages surveyed here. Its extra ownership does not eliminate the two app-specific seams and costs browser-native scroll/focus/click behavior. Native browser scrolling plus Framework7 PTR has less migration work for the existing DOM host, but retains cross-library interaction coordination.
- OpenSeadragon and Pixi Viewport are appropriate if the renderer moves to their scene/tile model. That transfer is a separate editor architecture decision.

### Gaps

- Framework7's bottom pull tracks one touch and has no explicit pen/finger/pinch arbitration contract. The current host's touch adapter must be accepted on real pen/touch hardware with one-finger fling, two-finger pinch, pen drawing, and held-release bottom pull operating together. — [PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js), [Editor.tsx](../../../hosts/web/src/editor/Editor.tsx)
- A desktop wheel cannot initiate Framework7 bottom PTR; its source enables wheel pull only for top PTR. The visible add-page command is the desktop route. — [PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js)

## What remains at the host boundary?

### Takeaway

The current DOM adapter classifies browser contact, sends raw pen samples to the existing engine, projects Framework7 scroll position and recognized pinch scale into the renderer view, and issues the add-page command after a held, completed bottom pull. Its owner split is evidence for the full-framework comparison.

### Cited Findings

- Pointer Events expose pointer type, pressure, tilt, twist, coalesced samples, and predicted samples; default touch manipulation is decided before pointer listeners, so a pen/finger split cannot be obtained by changing `touch-action` after contact. — [Pointer Events 3](https://www.w3.org/TR/pointerevents3/)
- Chromium's PDF ink host supplies a browser reference: it associates a pen `pointerdown` with a `touchstart`, cancels that touch sequence for ink, and leaves finger contact free to scroll. Its tests distinguish pen ink from finger gestures. This is a routing reference, not a replacement drawing engine. — [Chromium ink host](https://chromium.googlesource.com/chromium/src/+/be0366525a33fc4df00ab2b4164cb0f506dcc47b/chrome/browser/resources/pdf/elements/viewer-ink-host.ts), [gesture tests](https://chromium.googlesource.com/chromium/src/+/fcbdc2a473cb996c9e6b9382631ae8930924a22a/chrome/test/data/pdf/annotations_feature_enabled_test.ts)
- `@use-gesture/vanilla` supplies touch and trackpad pinch recognition with scale/origin callbacks, allowing the existing canvas renderer to retain its own document coordinates. — [gesture documentation](https://use-gesture.netlify.app/docs/gestures/)
- The current editor already sends non-touch pointer samples to the canvas engine, mirrors native `scrollTop` into the view, and uses Framework7's completed refresh event to call the document add-page command. — [Editor.tsx](../../../hosts/web/src/editor/Editor.tsx), [pointer adapter](../../../hosts/web/src/input/pointer.ts)

### Inferences

- The pen sample path can bypass framework state and the viewport recognizer. Framework7 and the browser see only enough input to keep their own gesture state; the C++ core keeps ink and history ownership.
- Device acceptance would be required for this owner split because its components share the same touch surface.

### Gaps

- The current editor has a capture-phase `touchmove` cancellation for pinch and bottom overscroll. Its need and event ordering must be demonstrated with a real mixed pen/touch device. If the framework's public event hooks cannot resolve a failure, adapt its pinned source in a licensed fork rather than adding a parallel gesture state machine. — [Editor.tsx](../../../hosts/web/src/editor/Editor.tsx), [Framework7 PTR source](https://github.com/framework7io/framework7/blob/v9.1.2/src/core/components/pull-to-refresh/pull-to-refresh-class.js)

Research queries: `Framework7 v9 pull to refresh bottom ptr bottom source touchmove page-content`; `Ionic ion-content scroll events refresher bottom pull up support`; `BetterScroll 2 pullup pulldown wheel zoom bounce pointer pen touch gesture`; `BetterScroll zoom plugin`; `BetterScroll v2.5.1 ActionsHandler touchstart pointerType`; `OpenSeadragon gestureSettingsPen flick pinch`; `pixi-viewport InputManager pointerType`; `Ionic Framework7 component catalog accessibility`.
