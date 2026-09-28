# Qt Quick and Flutter for the web host

## Which framework owns ordinary UI behavior?

### Takeaway

Select **Flutter with Cupertino and Material widgets for the web GUI**. It supplies one complete widget and interaction system and has a documented platform view for the HTML TikZ editor. Qt Quick with Qt Quick Controls is a credible alternative with stronger direct C++ and scene-graph integration, but its WebAssembly port requires more app-owned browser embedding and UI styling behavior.

### Cited Findings

- Qt Quick `Flickable` documents fling velocity, deceleration, drag overshoot, rebound, and live overshoot values. `PinchHandler` manages touch zoom and `PointerDeviceHandler` can filter pen, finger, and eraser input. — [Flickable](https://doc.qt.io/qt-6/qml-qtquick-flickable.html), [PinchHandler](https://doc.qt.io/qt-6/qml-qtquick-pinchhandler.html), [PointerDeviceHandler](https://doc.qt.io/qt-6/qml-qtquick-pointerdevicehandler.html)
- Qt Quick Controls supplies application windows, tabs, split views, scroll views, text fields, text areas, menus, and popups. — [Qt Quick Controls](https://doc.qt.io/qt-6/qtquickcontrols-index.html)
- Flutter supplies a complete Material and Cupertino widget system as well as gesture and scroll infrastructure. `InteractiveViewer` owns pan, pinch, scale limits, and deceleration; `Scrollable` owns configurable bounce physics. `photo_view` 0.15.0 provides `PhotoView.customChild` for a zoomable arbitrary widget within Flutter's gesture system; its device filtering needs a narrow extension if the stock recognizer accepts pen. — [Material widgets](https://docs.flutter.dev/ui/widgets/material), [Cupertino widgets](https://docs.flutter.dev/ui/widgets/cupertino), [InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html), [ScrollPhysics](https://api.flutter.dev/flutter/widgets/ScrollPhysics-class.html), [PhotoView.customChild](https://pub.dev/documentation/photo_view/latest/photo_view/PhotoView/PhotoView.customChild.html), [PhotoView gesture recognizer](https://github.com/renancaraujo/photo_view/blob/main/lib/src/core/photo_view_gesture_detector.dart)
- The current web host assembles SolidJS, Ionic, Framework7, Kobalte, corvu, use-gesture, and interact.js for controls and interactions. This is evidence of fragmented ownership, not a requirement to preserve that GUI implementation. — [repository architecture](../../ARCHITECTURE.md#integration-targets), [web host](../../ARCHITECTURE.md#current-web-host)

### Inferences

- Both complete frameworks remove the need to compose separate GUI libraries for controls, navigation, scrolling, and zoom. Qt owns those concerns cohesively and binds to the C++ engine directly. Flutter owns them cohesively too; a standard Dart/JavaScript interop boundary to the C++ WebAssembly core is an adapter, not novel application behavior.
- Flutter's Cupertino controls can be used on web, while Qt's documented iOS style is only available on macOS and iOS. Flutter also places an actual HTML editor inside the widget tree with `HtmlElementView`; Qt for WebAssembly has no documented WebEngine module and requires a separate DOM overlay. These two browser-facing ownership differences outweigh Qt's direct C++ binding for this application. — [Flutter Cupertino widgets](https://docs.flutter.dev/ui/widgets/cupertino), [Qt iOS style](https://doc.qt.io/qt-6/qtquickcontrols-ios.html), [Flutter HTML embedding](https://docs.flutter.dev/platform-integration/web/web-content-in-flutter), [Qt WebAssembly modules](https://doc.qt.io/qt-6/wasm.html)

### Gaps

- A passive Skia canvas in `HtmlElementView` and its gesture parent need device acceptance for pen/finger coexistence. This is integration work after selecting Flutter, not a reason to defer the owner decision.
- There is no defensible novel-LOC count for a Qt or Flutter implementation before a scoped build. The ownership comparison is qualitative and counts only behavior the application must create, not the number of dependencies or languages.

## What input and rendering adapters would each framework require?

### Takeaway

Qt's web port forwards pen pressure, tilt axes, and twist through its tablet event path, but the inspected path does not expand browser coalesced or predicted samples. Flutter expands coalesced samples but reduces the two tilt axes to one scalar; web C++ integration requires JavaScript interop. Both can be extended, yet neither offers a complete zero-adapter route to the current ink input record.

### Cited Findings

- Qt's WebAssembly `qwasmwindow.cpp` handles `pointermove` as one `PointerEvent`, forwards pressure and both tilt axes through `handleTabletEvent`, clamps each tilt axis to the Qt tablet range, and forwards twist as rotation. No `getCoalescedEvents` or `getPredictedEvents` call occurs in the inspected file. — [Qt WebAssembly pointer adapter](https://github.com/qt/qtbase/blob/dev/src/plugins/platforms/wasm/qwasmwindow.cpp)
- Qt provides a documented OpenGL framebuffer item for Qt Quick and documents inline custom scene-graph rendering. Its WebAssembly port uses WebGL. A Skia surface integration is therefore plausible through the documented rendering extension points, although an actual build remains to be shown. — [QQuickFramebufferObject](https://doc.qt.io/qt-6/qquickframebufferobject.html), [Qt scene graph](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html), [Qt WebAssembly](https://doc.qt.io/qt-6/wasm.html)
- Flutter's web `pointer_binding.dart` expands `getCoalescedEvents()` and forwards pressure, but `_computeHighestTilt` selects one of `tiltX` and `tiltY`; the public Flutter `PointerEvent` contains one `tilt` field and no predicted-sample field. No `getPredictedEvents` call occurs in the inspected adapter. — [Flutter web pointer binding](https://github.com/flutter/flutter/blob/main/engine/src/flutter/lib/web_ui/lib/src/engine/pointer_binding.dart), [Flutter PointerEvent](https://api.flutter.dev/flutter/gestures/PointerEvent-class.html)
- Dart's C FFI applies to Dart Native targets, while Dart web applications have JavaScript interop. Flutter can embed a DOM element via `HtmlElementView`, with documented hit-testing and pointer interception behavior. — [Dart C interop](https://dart.dev/interop/c-interop), [Dart JavaScript interop](https://dart.dev/interop/js-interop), [Flutter web embedding](https://docs.flutter.dev/platform-integration/web/web-content-in-flutter)
- Browser `getCoalescedEvents()` supplies intermediate movements for accurate pen paths. The existing host's input record accepts a batch and a predicted-sample flag. — [Pointer Events API](https://developer.mozilla.org/en-US/docs/Web/API/PointerEvent/getCoalescedEvents), [repository architecture](../../ARCHITECTURE.md#architecture)

### Inferences

- A narrow Qt platform-port fork could expand coalesced events before delivery. Preserving predicted-sample identity through the standard Qt tablet event is separate. A browser-event bridge scoped to the ink item can send raw pen batches to the engine while Qt owns finger navigation and regular controls.
- Flutter already expands browser coalesced events, but its public pointer record loses one tilt axis and does not mark predictions. Use a raw Pointer Events listener scoped to the notebook ink surface to send the complete pen batch to the existing C++ engine. Render Skia as a passive canvas within `HtmlElementView` so Flutter receives finger gestures; CSS `pointer-events: none` is the browser mechanism for passive hit testing. Configure Flutter's recognizers for finger input; `photo_view` needs a narrow fork or upstream extension if its `ScaleGestureRecognizer` accepts pen. This is a bounded host adapter, while Flutter owns gesture recognition and physics. — [Flutter pointer binding](https://github.com/flutter/flutter/blob/main/engine/src/flutter/lib/web_ui/lib/src/engine/pointer_binding.dart), [Flutter HTML embedding](https://docs.flutter.dev/platform-integration/web/web-content-in-flutter), [CSS pointer-events](https://developer.mozilla.org/en-US/docs/Web/CSS/pointer-events), [PhotoView recognizer](https://github.com/renancaraujo/photo_view/blob/main/lib/src/core/photo_view_gesture_detector.dart)

### Gaps

- The inspected Qt and Flutter source paths are live upstream branches, not immutable release pins. A pinned implementation would require source recheck at the selected release.
- A tested Flutter/Skia passive platform view and pointer bridge is needed before treating the integration as implemented. `pointer_interceptor` alone solves overlays above an `HtmlElementView`; it does not establish finger gesture delivery on the canvas itself. — [Flutter HTML embedding](https://docs.flutter.dev/platform-integration/web/web-content-in-flutter)

## Which complete web framework fits the independent UIKit host?

### Takeaway

Choose Flutter with Cupertino/Material widgets for the web host and UIKit for iPad. The GUI implementations can differ entirely. Flutter wins on complete inherited UI behavior plus documented browser embedding of the selected HTML editor; standard interop connects it to the authoritative C++/Skia core. Qt's C++ integration and `Flickable` are real advantages, but its WebAssembly HTML and iOS-style gaps leave more browser-facing application behavior to own.

### Cited Findings

- Qt for WebAssembly supports Qt Quick and Qt Quick Controls on desktop browsers. Its documented screen-reader support is basic and complex controls may have missing support. Its supported-module list does not include Qt WebEngine; Qt WebEngine's build platform notes list desktop platforms. — [Qt WebAssembly](https://doc.qt.io/qt-6/wasm.html), [Qt WebEngine platform notes](https://doc.qt.io/qt-6/qtwebengine-platform-notes.html)
- Flutter web can embed HTML inside a widget, but its documentation explains that the embedded element may intercept pointers and recommends an additional pointer interceptor around controls over it. Flutter web accessibility requires enabling a generated semantic HTML layer; standard widgets supply semantics. — [Flutter web embedding](https://docs.flutter.dev/platform-integration/web/web-content-in-flutter), [Flutter web accessibility](https://docs.flutter.dev/ui/accessibility/web-accessibility)
- Qt's iOS style documentation limits availability to macOS and iOS. Flutter documents Cupertino widgets in its cross-platform widget catalog. — [Qt iOS style](https://doc.qt.io/qt-6/qtquickcontrols-ios.html), [Flutter Cupertino widgets](https://docs.flutter.dev/ui/widgets/cupertino)
- UIKit's `UIScrollView` exposes its pan recognizer for precise control and its pinch recognizer for zoom. `UIGestureRecognizer.allowedTouchTypes` distinguishes direct touch from stylus input. — [UIScrollView pan recognizer](https://developer.apple.com/documentation/uikit/uiscrollview/pangesturerecognizer), [allowedTouchTypes](https://developer.apple.com/documentation/uikit/uigesturerecognizer/allowedtouchtypes)

### Inferences

- The selected HTML TikZ editor should remain a real browser iframe inside Flutter's documented `HtmlElementView`. Qt would have to place it above or beside the canvas with a separate layout/focus bridge because Qt WebEngine is not in the documented WebAssembly module set.
- UIKit directly supplies the iPad scroll and touch separation around the existing Metal surface. Cross-platform GUI reuse has no value in this decision.

### Gaps

- A physical pen/touch Chrome acceptance run must prove the Flutter integration: pen drawing with full samples, finger pan with velocity and rebound, pinch, bottom-edge held release, control focus, iframe focus, and keyboard navigation. These checks validate the chosen framework and its bridges; they do not postpone the choice.

## Search record

Searches on 2026-09-27 included: `Qt WebAssembly supported platforms accessibility mobile browsers limitations`, `Qt Flickable boundsBehavior rebound maximumFlickVelocity`, `Qt QQuickFramebufferObject OpenGL WebAssembly`, `Qt WebEngine WebAssembly supported modules`, `Flutter InteractiveViewer friction bouncing scroll physics`, `Flutter pointer_binding.dart getCoalescedEvents tilt pressure`, `Flutter HtmlElementView pointer interception`, `Dart FFI web support`, and `UIKit UIScrollView panGestureRecognizer allowedTouchTypes`. Sources inspected were Qt, Flutter, Dart, Apple, Framework7, and upstream Qt/Flutter source.
