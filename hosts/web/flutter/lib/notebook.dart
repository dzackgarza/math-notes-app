import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show SemanticsRole;
import 'dart:ui_web' as ui_web;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flex_color_picker/flex_color_picker.dart' show ColorWheelPicker;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:popover/popover.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:web/web.dart' as web;

import 'host.dart' as native;
import 'layers_sheet.dart';
import 'pages_sheet.dart';
import 'bookmarks_sheet.dart';
import 'figure_editor.dart';
import 'undo_dial.dart';

const accent = Color(0xFF2F6FEB);
const chrome = Color(0xFF151B2B);
const chromeBar = Color(0xFF1E2638);
const selectedFill = Color(0x662F6FEB);

typedef NotebookViewport = ({double scale, double x, double y, double scroll});
typedef NoteDestination = ({String noteKey, String file, String id});

String hex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0')}';

// The toolbar's tool kinds: key, label, and icon.
const toolKinds = [
  ('pen', 'Pen', LucideIcons.penTool),
  ('highlighter', 'Highlighter', LucideIcons.highlighter),
  ('eraser', 'Eraser', LucideIcons.eraser),
  ('lasso', 'Lasso', LucideIcons.lasso),
  ('text', 'Text', LucideIcons.type),
  ('image', 'Image', LucideIcons.image),
  ('space', 'Insert space', LucideIcons.moveVertical),
  ('drawing', 'Drawing mode', LucideIcons.spline),
];

class SelectionTransfer {
  const SelectionTransfer(this.read);
  final FutureOr<String> Function() read;
}

/// Claims each touch that lands during a pen stroke, so a resting palm
/// neither pans nor zooms the page. Saber gives every pointer of a gesture
/// that began as a stroke to the stroke the same way
/// (`isCurrentGestureADrawGesture` in its `InteractiveCanvas`).
class PalmRejection extends EagerGestureRecognizer {
  PalmRejection(this.stroking)
    : super(supportedDevices: {PointerDeviceKind.touch});
  final bool Function() stroking;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      stroking() && super.isPointerAllowed(event);
}

/// Recognizes a tap of several fingers with the limits of UIKit's
/// `UITapGestureRecognizer` and `numberOfTouchesRequired`: every finger
/// lifts before Flutter's long-press timeout and none moves beyond its tap
/// slop. A pen contact during the taps cancels the gesture.
class FingerTap {
  final origins = <int, Offset>{};
  int fingers = 0;
  Duration start = Duration.zero;
  bool valid = false;

  void cancel() => valid = false;

  /// The finger count of the tap that the touch [event] completes, or 0.
  int add(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (origins.isEmpty) {
        fingers = 0;
        start = event.timeStamp;
        valid = true;
      }
      origins[event.pointer] = event.position;
      if (origins.length > fingers) fingers = origins.length;
      return 0;
    }
    final origin = origins[event.pointer];
    if (origin == null) return 0;
    if ((event.position - origin).distance > kTouchSlop ||
        event is PointerCancelEvent)
      valid = false;
    if (event is! PointerUpEvent && event is! PointerCancelEvent) return 0;
    origins.remove(event.pointer);
    if (origins.isNotEmpty ||
        !valid ||
        event.timeStamp - start > kLongPressTimeout)
      return 0;
    return fingers;
  }
}

class Notebook extends StatefulWidget {
  const Notebook({
    super.key,
    required this.note,
    required this.engine,
    required this.onLibrary,
    required this.onConflicts,
    required this.active,
    required this.onCaptureChanged,
    required this.viewport,
    required this.linked,
    required this.destination,
    required this.onFollowLink,
    required this.onChooseNotebookLink,
    required this.tabsHidden,
    required this.onTabsHidden,
  });
  final native.OpenNote note;
  final native.Engine engine;
  final Future<void> Function() onLibrary;
  final Future<void> Function() onConflicts;
  final bool active;
  final ValueChanged<bool> onCaptureChanged;
  final ValueNotifier<NotebookViewport?> viewport;
  final bool linked;
  final ValueNotifier<NoteDestination?> destination;
  final Future<void> Function(String href, int page) onFollowLink;
  final Future<String?> Function(int page) onChooseNotebookLink;
  final bool tabsHidden;
  final ValueChanged<bool> onTabsHidden;
  @override
  State<Notebook> createState() => _NotebookState();
}

class _NotebookState extends State<Notebook>
    with SingleTickerProviderStateMixin {
  final scroll = ScrollController();
  final focus = FocusNode();
  bool applyingViewport = false;
  final transform = TransformationController();
  final element = web.HTMLCanvasElement();
  late final Ticker ticker;
  late final JSFunction saveListener;
  late final String viewType;
  native.Canvas? canvas;
  native.PenFile? pens;
  // The pen kind the palette and the pen settings change: pen or highlighter.
  String pen = 'pen';
  native.ToolSettings get penTool =>
      pen == 'highlighter' ? pens!.highlighter : pens!.pen;
  List<int> get palette => [
    for (final color in pens?.palette.toDart ?? <JSNumber>[]) color.toDartInt,
  ];
  int eraser = 0;
  String tool = 'pen';
  bool clippingsOpen = false;
  List<native.Clipping> clippings = [];
  bool drawing = false;
  final figureText = TextEditingController();
  String get figureSource => figureText.text;
  set figureSource(String value) => figureText.text = value;
  int selector = 0;
  int spaceMode = 6;
  String? failure;
  native.Selection? selection;
  double width = 1;
  double height = 1;
  double pixelRatio = 0;
  int page = 0;
  final touches = <int>{};
  final strokes = <int>{};
  final palms = <int>{};
  final taps = FingerTap();
  // One finger draws and two fingers pan and zoom. The choice belongs to the
  // device, so it lives in the browser's storage, not in the notes folder.
  // So do the toolbar side and the tool kinds that the toolbar hides.
  bool fingerDraws = web.window.localStorage.getItem('fingerDraws') == 'true';
  bool toolbarRight = web.window.localStorage.getItem('toolbarSide') == 'right';
  Set<String> hiddenTools = {
    ...?web.window.localStorage.getItem('hiddenTools')?.split(','),
  }..remove('');
  // The touch that draws the stroke in progress.
  int? fingerStroke;
  Timer? pullTimer;
  bool pullReady = false;
  bool atEnd = false;
  static int nextView = 0;

  double get fit => width / widget.note.document.contentSize().width;
  String get layerLabel {
    final index = canvas?.activeLayer() ?? -1;
    if (index < 0) return 'Choose a layer';
    final layer = widget.note.document.layers().toDart[index];
    return '${layer.name}${layer.hidden
        ? " (hidden)"
        : layer.locked
        ? " (locked)"
        : ""}';
  }

  String get saveLabel => drawing
      ? 'Drawing in progress'
      : switch (widget.note.saver.state.status) {
          'saved' => 'Saved',
          'pending' => 'Unsaved changes',
          'recoverable' => 'Pending file save',
          'saving' => 'Saving…',
          'error' => 'Save failed',
          final state => throw StateError('Invalid save state: $state'),
        };

  @override
  void initState() {
    super.initState();
    viewType = 'notebook-${nextView++}';
    element.style.width = '100%';
    element.style.height = '100%';
    element.style.pointerEvents = 'none';
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int id) => element,
    );
    saveListener = ((web.Event event) {
      if (mounted) setState(() {});
    }).toJS;
    widget.note.saver.addEventListener('change', saveListener);
    scroll.addListener(updateView);
    transform.addListener(updateView);
    widget.viewport.addListener(receiveViewport);
    widget.destination.addListener(receiveDestination);
    ticker = createTicker((_) {
      canvas?.render();
      final next = canvas?.selection();
      if (next?.count != selection?.count ||
          next?.x != selection?.x ||
          next?.y != selection?.y ||
          next?.width != selection?.width ||
          next?.height != selection?.height) {
        setState(() => selection = next);
        if (!drawing && canvas!.selectedFigure().isNotEmpty) {
          setState(
            () => figureSource = native.host.figureSource(
              widget.note,
              canvas!,
              false,
            ),
          );
        }
      }
    })..start();
    unawaited(
      run(() async {
        pens = await native.host
            .readPens(widget.note.root, widget.engine)
            .toDart;
        canvas = await native.host.mountCanvas(widget.note, element).toDart;
        canvas!.setTool(penTool);
        updateView();
        receiveDestination();
      }),
    );
  }

  @override
  void didUpdateWidget(Notebook oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) focus.requestFocus();
      });
    }
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => failure = null);
    } catch (error) {
      if (mounted) setState(() => failure = error.toString());
    }
  }

  void updateView() {
    final target = canvas;
    if (target == null) return;
    final matrix = transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    updatePull();
    final ratio = web.window.devicePixelRatio;
    final pixelsWide = (width * ratio).round();
    final pixelsHigh = (height * ratio).round();
    if (element.width != pixelsWide ||
        element.height != pixelsHigh ||
        pixelRatio != ratio) {
      element.width = pixelsWide;
      element.height = pixelsHigh;
      pixelRatio = ratio;
      target.setSurfaceSize(
        pixelsWide.toDouble(),
        pixelsHigh.toDouble(),
        ratio,
      );
    }
    target.setView(
      fit * scale,
      0,
      0,
      fit * scale,
      matrix.storage[12],
      matrix.storage[13] - offset * scale,
    );
    final current = target.pageAt(width / 2, height / 2);
    if (current >= 0 && current != page && mounted)
      setState(() => page = current);
    if (widget.linked && widget.active && !applyingViewport && fit > 0) {
      widget.viewport.value = (
        scale: scale,
        x: matrix.storage[12] / fit,
        y: matrix.storage[13] / fit,
        scroll: offset / fit,
      );
    }
  }

  void receiveViewport() {
    if (!widget.linked || widget.active) return;
    final view = widget.viewport.value;
    if (view == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.linked || widget.active || !scroll.hasClients)
        return;
      applyingViewport = true;
      transform.value = Matrix4.identity()
        ..setEntry(0, 0, view.scale)
        ..setEntry(1, 1, view.scale)
        ..setEntry(0, 3, view.x * fit)
        ..setEntry(1, 3, view.y * fit);
      scroll.jumpTo(
        (view.scroll * fit).clamp(0.0, scroll.position.maxScrollExtent),
      );
      applyingViewport = false;
    });
  }

  void input(PointerEvent event) {
    if (event is PointerDownEvent) focus.requestFocus();
    final ended = event is PointerUpEvent || event is PointerCancelEvent;
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      if (event is PointerDownEvent) {
        strokes.add(event.pointer);
        taps.cancel();
      }
      if (ended) strokes.remove(event.pointer);
    }
    if (event.kind == PointerDeviceKind.touch) {
      if (event is PointerDownEvent && strokes.isNotEmpty)
        palms.add(event.pointer);
      if (fingerDraws &&
          event is PointerDownEvent &&
          !palms.contains(event.pointer)) {
        if (fingerStroke != null && canvas != null)
          native.host.cancelStroke(canvas!);
        fingerStroke = touches.isEmpty ? event.pointer : null;
      }
      if (palms.contains(event.pointer)) {
        if (ended) palms.remove(event.pointer);
        return;
      }
      switch (taps.add(event)) {
        case 2:
          history(false);
        case 3:
          history(true);
      }
      if (event is PointerDownEvent) touches.add(event.pointer);
      if (ended) {
        final add = event is PointerUpEvent && touches.length == 1 && pullReady;
        touches.remove(event.pointer);
        cancelPull();
        if (add) addPage();
      }
      updatePull();
    }
    final target = canvas;
    final finger = event.pointer == fingerStroke;
    if (finger && ended) fingerStroke = null;
    if (tool == 'navigate' || tool == 'bookmark' || tool == 'text') return;
    if (target == null ||
        (event.kind != PointerDeviceKind.stylus &&
            event.kind != PointerDeviceKind.invertedStylus &&
            !finger))
      return;
    if (native.host.acceptPen(
      target,
      element,
      event.timeStamp.inMicroseconds.toDouble(),
      fingerDraws,
    )) {
      if (drawing)
        setState(
          () => figureSource = native.host.figureSource(
            widget.note,
            target,
            true,
          ),
        );
      else
        widget.note.saver.schedule();
    }
  }

  void cancelPull() {
    pullTimer?.cancel();
    if (pullTimer != null || pullReady) {
      setState(() {
        pullTimer = null;
        pullReady = false;
      });
    }
  }

  void updatePull() {
    if (!scroll.hasClients) return;
    if (drawing) {
      cancelPull();
      if (atEnd) setState(() => atEnd = false);
      return;
    }
    final beyond = scroll.offset - scroll.position.maxScrollExtent;
    final end = beyond >= -1;
    if (atEnd != end) setState(() => atEnd = end);
    if (touches.length != 1 || beyond < 96) {
      cancelPull();
      return;
    }
    if (pullTimer == null) {
      setState(() {
        pullTimer = Timer(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => pullReady = true);
        });
      });
    }
  }

  void addPage() {
    if (drawing) return;
    edit(
      () => widget.note.document.insertPage(widget.note.document.pageCount()),
    );
  }

  bool history(bool redo) {
    if (drawing) return false;
    final step = redo
        ? widget.note.document.redo()
        : widget.note.document.undo();
    if (step == null) return false;
    widget.note.saver.schedule();
    setState(
      () => page = step.page.clamp(0, widget.note.document.pageCount() - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) jump(page);
    });
    return true;
  }

  Future<void> textAt(Offset point) async {
    final target = canvas;
    if (target == null) return;
    final existing = target.selectTextAt(point.dx, point.dy);
    final properties = existing ? target.textProperties() : null;
    var rtl = properties?.rtl ?? false;
    final boxWidth = TextEditingController(
      text: (properties?.width ?? 300).toString(),
    );
    final controller = TextEditingController(text: properties?.content ?? '');
    String? validation;
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CupertinoAlertDialog(
          title: Text(existing ? 'Edit text' : 'Insert text'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: controller,
                  autofocus: true,
                  placeholder: 'Text',
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'NoteText',
                    fontFamilyFallback: [
                      'Noto Sans Arabic',
                      'Noto Sans Hebrew',
                      'Noto Sans Devanagari',
                      'Noto Sans Symbols2',
                    ],
                    fontSize: 18,
                  ),
                  minLines: 3,
                  maxLines: 8,
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: boxWidth,
                  prefix: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Width (pt)'),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const Text('Use 0 for the full text width.'),
                if (validation != null)
                  Text(
                    validation!,
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
                Row(
                  children: [
                    const Expanded(child: Text('Right to left')),
                    CupertinoSwitch(
                      value: rtl,
                      onChanged: (value) => update(() => rtl = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final width = double.tryParse(boxWidth.text);
                if (width == null ||
                    !width.isFinite ||
                    width < 0 ||
                    width > 100000) {
                  update(() => validation = 'Use a width from 0 to 100000 pt.');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && controller.text.isNotEmpty) {
      final width = double.parse(boxWidth.text);
      edit(
        () => target.editText(
          native.TextBoxProperties(
            content: controller.text,
            width: width,
            rtl: rtl,
          ),
          point.dx,
          point.dy,
          existing,
        ),
      );
    } else if (accepted == true && existing) {
      edit(() => target.deleteSelection());
    }
    controller.dispose();
    boxWidth.dispose();
  }

  Future<void> copy(bool cut) async {
    final target = canvas;
    if (target == null) return;
    final svg = target.copySelection(false);
    if (svg.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: svg));
    if (cut) edit(() => target.deleteSelection());
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final svg = data?.text;
    if (svg != null && svg.isNotEmpty)
      edit(() => canvas!.paste(svg, width / 2, height / 2));
  }

  void edit(void Function() action) {
    action();
    widget.note.saver.schedule();
    setState(() {});
    updateView();
  }

  void chooseTool(String value) {
    setState(() => tool = value);
    final ruledErase = value == 'eraser' && eraser == 2;
    canvas?.setEraser(
      eraser == 2 ? 0 : eraser,
      value == 'eraser' && !ruledErase,
    );
    canvas?.setSelector(
      value == 'space'
          ? spaceMode
          : ruledErase
          ? 3
          : selector,
      value == 'lasso' || value == 'space' || ruledErase,
    );
    if (value == 'pen' || value == 'highlighter') {
      pen = value;
      canvas?.setTool(penTool);
    }
  }

  Future<void> refreshClippings() async {
    final values = await native.host
        .listClippings(widget.engine, widget.note.root)
        .toDart;
    if (mounted) setState(() => clippings = values.toDart);
  }

  Future<String> clippingSource(native.Clipping item) async =>
      (await native.host
              .clippingSvg(widget.engine, widget.note.root, item.id)
              .toDart)
          .toDart;

  void toggleFingerDrawing() {
    setState(() => fingerDraws = !fingerDraws);
    web.window.localStorage.setItem('fingerDraws', '$fingerDraws');
  }

  // With finger drawing the scroll view ignores touch and InteractiveViewer
  // does not pan, so a one-finger stroke leaves the page still. Two fingers
  // move the page here; a pinch still zooms through InteractiveViewer.
  void fingerPan(ScaleUpdateDetails details) {
    if (details.pointerCount < 2 || details.scale != 1.0) return;
    final scale = transform.value.getMaxScaleOnAxis();
    final x = (transform.value.getTranslation().x + details.focalPointDelta.dx)
        .clamp(width * (1 - scale), 0.0);
    transform.value = transform.value.clone()..setEntry(0, 3, x);
    scroll.jumpTo(
      (scroll.offset - details.focalPointDelta.dy / scale).clamp(
        0.0,
        scroll.position.maxScrollExtent,
      ),
    );
  }

  void toggleDrawing() {
    if (canvas == null) return;
    if (drawing) {
      final id = native.host.finishFigure(canvas!);
      drawing = false;
      widget.onCaptureChanged(false);
      edit(() {});
      if (id.isNotEmpty) unawaited(run(() => editFigure(id)));
    } else {
      canvas!.beginFigure(page);
      chooseTool(pen);
      drawing = true;
      widget.onCaptureChanged(true);
      setState(
        () =>
            figureSource = native.host.figureSource(widget.note, canvas!, true),
      );
    }
  }

  Future<void> editFigure(String id) async {
    widget.onCaptureChanged(true);
    try {
      await Navigator.of(context).push<void>(
        CupertinoPageRoute(
          builder: (context) => FigureEditor(note: widget.note, id: id),
        ),
      );
    } finally {
      widget.onCaptureChanged(false);
      if (mounted) setState(() {});
    }
  }

  // The paper of the page and the size of new pages.
  Future<void> paperMenu() async {
    final templates = await native.host.listTemplates(widget.note.root).toDart;
    if (!mounted) return;
    Future<void> applyTemplate(String name) async {
      await native.host
          .applyTemplate(widget.note.root, widget.note.document, name)
          .toDart;
      widget.note.template = name;
      edit(() {});
    }

    final chosen = await showCupertinoModalPopup<Future<void> Function()>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Paper'),
        actions: [
          for (final name in templates.toDart)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.pop(context, () => applyTemplate(name.toDart)),
              child: Text(name.toDart),
            ),
          for (final (size, orientation, label) in const [
            (0, 0, 'New pages: A4 portrait'),
            (0, 1, 'New pages: A4 landscape'),
            (1, 0, 'New pages: Letter portrait'),
            (1, 1, 'New pages: Letter landscape'),
          ])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(
                context,
                () async => edit(
                  () => widget.note.document.setPageSize(size, orientation),
                ),
              ),
              child: Text(label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    await chosen?.call();
  }

  void insertPage(int at) => edit(() => widget.note.document.insertPage(at));

  void deletePage() => edit(() {
    widget.note.document.deletePage(page);
    page = page.clamp(0, widget.note.document.pageCount() - 1);
  });

  Future<void> showPages() async {
    final chosen = await overviewPages(
      context,
      widget.note.document,
      page,
      edit,
    );
    if (chosen != null) jump(chosen);
  }

  // The popover beside a toolbar button, on the page side of the toolbar.
  Future<void> popover(
    BuildContext anchor,
    String label,
    double width,
    Widget Function(BuildContext context, StateSetter update) body,
  ) async {
    await showPopover<void>(
      context: anchor,
      direction: toolbarRight ? PopoverDirection.left : PopoverDirection.right,
      width: width,
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      barrierColor: const Color(0x00000000),
      barrierLabel: 'Close $label',
      bodyBuilder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(16),
          child: body(context, update),
        ),
      ),
    );
  }

  // The eraser, lasso, and insert space modes.
  Future<void> modePopover(String kind, BuildContext anchor) {
    final (label, modes, current) = switch (kind) {
      'eraser' => (
        'Eraser',
        const {0: 'Stroke', 1: 'Partial', 2: 'Ruled'},
        eraser,
      ),
      'lasso' => (
        'Lasso',
        const {0: 'Freehand', 1: 'Rectangle', 7: 'Oval', 2: 'Ruled'},
        selector,
      ),
      _ => (
        'Insert space',
        const {4: 'Vertical', 5: 'Horizontal', 6: 'Reflow'},
        spaceMode,
      ),
    };
    var value = current;
    return popover(
      anchor,
      '$label modes',
      340,
      (context, update) => CupertinoSlidingSegmentedControl<int>(
        groupValue: value,
        children: {
          for (final mode in modes.entries) mode.key: Text(mode.value),
        },
        onValueChanged: (next) {
          if (next == null) return;
          update(() => value = next);
          switch (kind) {
            case 'eraser':
              eraser = next;
            case 'lasso':
              selector = next;
            default:
              spaceMode = next;
          }
          chooseTool(kind);
        },
      ),
    );
  }

  // Noteful's pen popover: a sample stroke, the pen types, size presets and a
  // slider, opacity on the Advanced tab, and Save. The selected kind changes
  // once, when the popover closes.
  Future<void> configurePen(BuildContext anchor) async {
    if (pens == null) return;
    final highlighter = pen == 'highlighter';
    final original = penTool;
    var brush = original.brush;
    var size = original.size;
    var opacity = original.opacity;
    final rgb = original.rgb;
    var advanced = false;
    var save = false;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    native.ToolSettings settings() => native.ToolSettings.create(
      brush: brush,
      rgb: rgb,
      size: size,
      opacity: opacity,
    );
    await popover(anchor, '$pen settings', 320, (context, update) {
      final presets = highlighter
          ? const [4.8, 7.2, 9.6, 14.4, 19.2]
          : const [0.6, 1.2, 1.8, 2.4, 3.6];
      final opacityRow = Row(
        children: [
          const Text('Opacity'),
          Expanded(
            child: CupertinoSlider(
              value: opacity,
              min: 0.1,
              max: 1,
              divisions: 9,
              onChanged: (value) => update(() => opacity = value),
            ),
          ),
          Text('${(opacity * 100).round()}%'),
        ],
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            highlighter ? 'Highlighter' : 'Pen',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          Image.memory(
            native.host
                .penPreview(
                  widget.engine,
                  settings(),
                  (288 * ratio).round(),
                  (64 * ratio).round(),
                  1.5 * ratio,
                )
                .toDart,
            width: 288,
            height: 64,
            gaplessPlayback: true,
          ),
          if (!highlighter)
            CupertinoSlidingSegmentedControl<bool>(
              groupValue: advanced,
              children: const {false: Text('Settings'), true: Text('Advanced')},
              onValueChanged: (value) => update(() => advanced = value!),
            ),
          if (!highlighter && !advanced)
            CupertinoSlidingSegmentedControl<int>(
              groupValue: brush,
              children: const {0: Text('Pen'), 1: Text('Marker')},
              onValueChanged: (value) => update(() => brush = value!),
            ),
          if (highlighter || !advanced) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (i, value) in presets.indexed)
                  Semantics(
                    label: '$value pt',
                    button: true,
                    excludeSemantics: true,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 40),
                      onPressed: () => update(() => size = value),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (size - value).abs() < 0.05
                                ? CupertinoColors.activeBlue
                                : const Color(0x00000000),
                            width: 2,
                          ),
                        ),
                        child: Container(
                          width: 4.0 + 5 * i,
                          height: 4.0 + 5 * i,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF000000 | rgb),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                const Text('Size'),
                Expanded(
                  child: CupertinoSlider(
                    value: size.clamp(0.2, 20),
                    min: 0.2,
                    max: 20,
                    divisions: 99,
                    onChanged: (value) => update(() => size = value),
                  ),
                ),
                Text('${size.toStringAsFixed(1)} pt'),
              ],
            ),
          ],
          if (highlighter || advanced) opacityRow,
          CupertinoButton(
            onPressed: () {
              save = true;
              Navigator.pop(context);
            },
            child: const Text('Save pen'),
          ),
        ],
      );
    });
    if (brush != original.brush ||
        size != original.size ||
        opacity != original.opacity) {
      await updatePen(settings());
    }
    if (save) await writePens(saved: [...savedPens, settings()]);
  }

  // Writes .pens.json with the given parts replaced.
  Future<void> writePens({
    native.ToolSettings? pen,
    native.ToolSettings? highlighter,
    List<int>? palette,
    List<native.ToolSettings>? saved,
  }) async {
    final next = native.PenFile.create(
      pen: pen ?? pens!.pen,
      highlighter: highlighter ?? pens!.highlighter,
      palette: [for (final color in palette ?? this.palette) color.toJS].toJS,
      saved: saved?.toJS ?? pens!.saved,
    );
    await native.host.writePens(widget.note.root, widget.engine, next).toDart;
    setState(() => pens = next);
  }

  List<native.ToolSettings> get savedPens => pens?.saved.toDart ?? [];

  // Replaces the selected kind's settings; later strokes use them.
  Future<void> updatePen(native.ToolSettings settings) async {
    await writePens(
      pen: pen == 'pen' ? settings : null,
      highlighter: pen == 'highlighter' ? settings : null,
    );
    chooseTool(pen);
  }

  Future<void> choosePenColor(int rgb) async {
    if (pens == null) return;
    final current = penTool;
    await updatePen(
      native.ToolSettings.create(
        brush: current.brush,
        rgb: rgb,
        size: current.size,
        opacity: current.opacity,
      ),
    );
  }

  // A saved pen is a shortcut to the pen or highlighter settings it holds.
  Future<void> applySaved(native.ToolSettings settings) async {
    pen = settings.brush == 2 ? 'highlighter' : 'pen';
    await updatePen(settings);
  }

  Future<void> savedPenMenu(int index) async {
    final remove = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove saved pen'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (remove == true) await writePens(saved: [...savedPens]..removeAt(index));
  }

  // A swatch recolors the selection when there is one. Otherwise it sets the
  // pen or highlighter color, and a tap on the current color edits it.
  Future<void> tapSwatch(BuildContext anchor, int index) async {
    final color = palette[index];
    if (selection != null) {
      edit(() => canvas!.recolorSelection(color));
      return;
    }
    if ((tool == 'pen' || tool == 'highlighter') && penTool.rgb == color) {
      await editSwatch(anchor, index);
      return;
    }
    await choosePenColor(color);
  }

  Widget colorWheel(int rgb, ValueChanged<int> changed) => SizedBox(
    width: 228,
    height: 228,
    child: ColorWheelPicker(
      color: Color(0xFF000000 | rgb),
      onChanged: (color) => changed(color.toARGB32() & 0xFFFFFF),
      onWheel: (_) {},
      wheelWidth: 20,
    ),
  );

  Future<void> editSwatch(BuildContext anchor, int index) async {
    var rgb = palette[index];
    await popover(
      anchor,
      'color',
      260,
      (context, update) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(hex(rgb)),
          const SizedBox(height: 8),
          colorWheel(rgb, (next) => update(() => rgb = next)),
        ],
      ),
    );
    if (rgb == palette[index]) return;
    await writePens(palette: [...palette]..[index] = rgb);
    await choosePenColor(rgb);
  }

  Future<void> editPalette(BuildContext anchor) async {
    final colors = palette;
    var rgb = penTool.rgb;
    await popover(
      anchor,
      'color list',
      280,
      (context, update) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (i, color) in colors.indexed)
                Semantics(
                  label: 'Remove color ${hex(color)}',
                  button: true,
                  excludeSemantics: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: () => update(() => colors.removeAt(i)),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF000000 | color),
                        border: Border.all(color: CupertinoColors.systemGrey4),
                      ),
                      child: const Icon(
                        LucideIcons.x,
                        size: 14,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          colorWheel(rgb, (next) => update(() => rgb = next)),
          CupertinoButton(
            onPressed: () => update(() => colors.add(rgb)),
            child: const Text('Add color'),
          ),
        ],
      ),
    );
    if (!listEquals(colors, palette)) await writePens(palette: colors);
  }

  Widget toolButton(
    String label,
    IconData icon, {
    bool selected = false,
    Color color = CupertinoColors.white,
    void Function(BuildContext anchor)? onPressed,
    VoidCallback? onLongPress,
  }) => Builder(
    builder: (anchor) => Semantics(
      label: label,
      selected: selected,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onPressed == null ? null : () => onPressed(anchor),
        onLongPress: onLongPress,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? selectedFill : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    ),
  );

  // A tap on an unselected tool chooses it; a tap on the selected tool opens
  // its settings. Image, text, and drawing mode act at once.
  void tapTool(String kind, BuildContext anchor) {
    switch (kind) {
      case 'image':
        unawaited(
          run(() async {
            final inserted = await native.host
                .insertImage(widget.note, canvas!, page, width / 2, height / 2)
                .toDart;
            if (inserted.toDart) widget.note.saver.schedule();
          }),
        );
      case 'drawing':
        toggleDrawing();
      case 'text':
        chooseTool('text');
        unawaited(textAt(Offset(width / 2, height / 2)));
      case _ when tool != kind:
        chooseTool(kind);
      case 'pen' || 'highlighter':
        unawaited(run(() => configurePen(anchor)));
      default:
        unawaited(run(() => modePopover(kind, anchor)));
    }
  }

  Widget swatch(int index, int color) {
    final current = pens != null && penTool.rgb == color;
    return Builder(
      builder: (anchor) => Semantics(
        label: 'Color ${hex(color)}',
        selected: current,
        button: true,
        excludeSemantics: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 36),
          onPressed: () => run(() => tapSwatch(anchor, index)),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF000000 | color),
              border: Border.all(
                color: current
                    ? CupertinoColors.white
                    : const Color(0x55FFFFFF),
                width: current ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The floating toolbar (docs/specs/tablet-ui.md, Editor): the tools, a
  // divider, then undo, redo, saved pens, swatches, and the color list.
  Widget toolbar() => Container(
    width: 52,
    margin: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: chromeBar,
      borderRadius: BorderRadius.circular(14),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (kind, label, icon) in toolKinds)
            if (!hiddenTools.contains(kind))
              toolButton(
                kind == 'drawing' && drawing ? 'Complete drawing' : label,
                icon,
                selected: kind == 'drawing' ? drawing : tool == kind,
                onPressed: canvas == null || (kind == 'space' && drawing)
                    ? null
                    : (anchor) => tapTool(kind, anchor),
              ),
          Container(
            width: 28,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: const Color(0x33FFFFFF),
          ),
          UndoDial(
            enabled: !drawing,
            pageOnLeft: toolbarRight,
            onStep: (direction) => history(direction > 0),
            child: Semantics(
              label: 'Undo',
              button: true,
              enabled: !drawing,
              onTap: () => history(false),
              excludeSemantics: true,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  LucideIcons.undo2,
                  color: drawing
                      ? CupertinoColors.inactiveGray
                      : CupertinoColors.white,
                ),
              ),
            ),
          ),
          toolButton(
            'Redo',
            LucideIcons.redo2,
            onPressed: drawing ? null : (_) => history(true),
          ),
          for (final (i, saved) in savedPens.indexed)
            toolButton(
              'Saved pen ${saved.size.toStringAsFixed(1)} pt ${hex(saved.rgb)}',
              saved.brush == 2 ? LucideIcons.highlighter : LucideIcons.penTool,
              color: Color(0xFF000000 | saved.rgb),
              onPressed: (_) => run(() => applySaved(saved)),
              onLongPress: () => run(() => savedPenMenu(i)),
            ),
          for (final (i, color) in palette.indexed) swatch(i, color),
          toolButton(
            'Edit colors',
            LucideIcons.plus,
            onPressed: pens == null
                ? null
                : (anchor) => run(() => editPalette(anchor)),
          ),
        ],
      ),
    ),
  );

  // Overlays on the page: the active mode, the selection actions, and the
  // page number.
  List<Widget> overlays() {
    final mode = drawing
        ? 'Drawing mode'
        : switch (tool) {
            'space' => 'Insert space',
            'text' => 'Text',
            'bookmark' => 'Add bookmark',
            'navigate' => 'Follow links',
            _ => null,
          };
    final area = selection;
    const white = TextStyle(color: CupertinoColors.white);
    return [
      if (mode != null)
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                color: chromeBar,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(mode, style: white),
                  if (tool == 'bookmark' && !drawing)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        'Tap the line to mark.',
                        style: TextStyle(color: CupertinoColors.systemGrey),
                      ),
                    ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(36, 36),
                    onPressed: drawing ? toggleDrawing : () => chooseTool(pen),
                    child: drawing
                        ? const Text('Complete')
                        : Semantics(
                            label: 'Close $mode',
                            button: true,
                            excludeSemantics: true,
                            child: const Icon(
                              LucideIcons.x,
                              color: CupertinoColors.white,
                              size: 18,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (area != null && canvas != null)
        Positioned(
          top: area.y + area.height + 60 < height
              ? area.y + area.height + 8
              : (area.y - 60).clamp(8.0, height - 60),
          left: 0,
          right: 0,
          child: Center(child: selectionMenu()),
        ),
      Positioned(
        bottom: 12,
        right: 12,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: chromeBar,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Semantics(
              container: true,
              child: Text(
                '${page + 1} / ${widget.note.document.pageCount()}',
                style: white,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget selectionMenu() {
    final figure = !drawing && canvas!.selectedFigure().isNotEmpty;
    Widget action(String label, IconData icon, VoidCallback onPressed) =>
        toolButton(label, icon, onPressed: (_) => onPressed());
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: chromeBar,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        children: [
          LongPressDraggable<SelectionTransfer>(
            data: SelectionTransfer(() => canvas!.copySelection(false)),
            feedback: const DecoratedBox(
              decoration: BoxDecoration(color: CupertinoColors.systemGrey5),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Copy selection'),
              ),
            ),
            child: Semantics(
              label: 'Drag a copy',
              excludeSemantics: true,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(LucideIcons.grab, color: CupertinoColors.white),
              ),
            ),
          ),
          action('Copy', LucideIcons.copy, () => run(() => copy(false))),
          action('Cut', LucideIcons.scissors, () => run(() => copy(true))),
          action(
            'Duplicate',
            LucideIcons.copyPlus,
            () => edit(() => canvas!.duplicateSelection()),
          ),
          action(
            'Delete selection',
            LucideIcons.trash2,
            () => edit(() => canvas!.deleteSelection()),
          ),
          action(
            'Link selected content',
            LucideIcons.link,
            () => run(linkSelection),
          ),
          action(
            'Bookmark selection',
            LucideIcons.bookmark,
            () => edit(() => canvas!.bookmarkSelection()),
          ),
          action(
            'Remove bookmark or link',
            LucideIcons.unlink,
            () => edit(() => canvas!.ungroupSelection()),
          ),
          if (clippingsOpen && !drawing)
            action(
              'Save to clippings',
              LucideIcons.inbox,
              () => run(() async {
                await native.host
                    .saveClipping(
                      widget.engine,
                      widget.note.root,
                      canvas!.copySelection(false),
                    )
                    .toDart;
                await refreshClippings();
              }),
            ),
          if (figure)
            action(
              'Edit figure',
              LucideIcons.spline,
              () => run(() => editFigure(canvas!.selectedFigure())),
            ),
          action(
            'Clear selection',
            LucideIcons.x,
            () => canvas!.clearSelection(),
          ),
        ],
      ),
    );
  }

  Widget menuButton(
    String label,
    IconData icon,
    List<PullDownMenuEntry> Function() items,
  ) => PullDownButton(
    itemBuilder: (_) => items(),
    buttonBuilder: (context, showMenu) => Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onPressed: showMenu,
        child: Icon(icon),
      ),
    ),
  );

  List<PullDownMenuEntry> pagesMenu() => [
    PullDownMenuTitle(
      title: Text('Page ${page + 1} of ${widget.note.document.pageCount()}'),
    ),
    PullDownMenuItem(
      title: 'Page overview',
      enabled: !drawing,
      onTap: () => run(showPages),
    ),
    PullDownMenuItem(
      title: 'Previous page',
      enabled: page > 0,
      onTap: () => jump(page - 1),
    ),
    PullDownMenuItem(
      title: 'Next page',
      enabled: page + 1 < widget.note.document.pageCount(),
      onTap: () => jump(page + 1),
    ),
    PullDownMenuItem(title: 'Bookmarks', onTap: () => run(bookmarks)),
    PullDownMenuItem(
      title: 'Add bookmark',
      enabled: !drawing,
      onTap: () {
        if (selection != null)
          edit(() => canvas!.bookmarkSelection());
        else
          chooseTool('bookmark');
      },
    ),
    PullDownMenuItem(
      title: 'Layers',
      subtitle: layerLabel,
      enabled: !drawing && canvas != null,
      onTap: () =>
          run(() => manageLayers(context, widget.note.document, canvas!, edit)),
    ),
    const PullDownMenuDivider.large(),
    PullDownMenuItem(title: 'Add page', enabled: !drawing, onTap: addPage),
    PullDownMenuItem(
      title: 'Insert page before',
      enabled: !drawing,
      onTap: () => insertPage(page),
    ),
    PullDownMenuItem(
      title: 'Insert page after',
      enabled: !drawing,
      onTap: () => insertPage(page + 1),
    ),
  ];

  List<PullDownMenuEntry> viewMenu() => [
    PullDownMenuItem.selectable(
      title: 'Fit width',
      selected: transform.value.getMaxScaleOnAxis() == 1,
      onTap: fitWidth,
    ),
    const PullDownMenuDivider.large(),
    for (final right in [false, true])
      PullDownMenuItem.selectable(
        title: right ? 'Toolbar on right' : 'Toolbar on left',
        selected: toolbarRight == right,
        onTap: () {
          setState(() => toolbarRight = right);
          web.window.localStorage.setItem(
            'toolbarSide',
            right ? 'right' : 'left',
          );
        },
      ),
    PullDownMenuItem(
      title: widget.tabsHidden ? 'Show tab bar' : 'Hide tab bar',
      onTap: () => widget.onTabsHidden(!widget.tabsHidden),
    ),
  ];

  List<PullDownMenuEntry> moreMenu() => [
    PullDownMenuItem(
      title: 'Paper',
      enabled: !drawing,
      onTap: () => run(paperMenu),
    ),
    PullDownMenuItem(
      title: 'Export PDF',
      enabled: !drawing,
      onTap: () => run(exportPdf),
    ),
    PullDownMenuItem(
      title: 'Go to page',
      enabled: !drawing,
      onTap: () => run(goToPage),
    ),
    PullDownMenuItem(
      title: 'Select page',
      onTap: () => canvas?.selectAll(page),
    ),
    PullDownMenuItem(
      title: 'Clear page',
      enabled: !drawing && canvas != null,
      onTap: () {
        canvas!.selectAll(page);
        edit(() => canvas!.deleteSelection());
      },
    ),
    PullDownMenuItem(
      title: 'Delete page',
      isDestructive: true,
      enabled: !drawing && widget.note.document.pageCount() > 1,
      onTap: deletePage,
    ),
    const PullDownMenuDivider.large(),
    PullDownMenuItem.selectable(
      title: 'Draw with finger',
      selected: fingerDraws,
      onTap: toggleFingerDrawing,
    ),
    PullDownMenuItem(
      title: 'Customize toolbar',
      onTap: () => run(customizeToolbar),
    ),
    const PullDownMenuDivider.large(),
    PullDownMenuItem(title: 'Paste', onTap: () => run(paste)),
    PullDownMenuItem.selectable(
      title: 'Clippings',
      selected: clippingsOpen,
      onTap: () => run(() async {
        if (!clippingsOpen) await refreshClippings();
        setState(() => clippingsOpen = !clippingsOpen);
      }),
    ),
    PullDownMenuItem(
      title: 'Compare versions',
      enabled: !drawing,
      onTap: () => run(widget.onConflicts),
    ),
    PullDownMenuItem.selectable(
      title: 'Follow links',
      selected: tool == 'navigate',
      onTap: () => chooseTool(tool == 'navigate' ? pen : 'navigate'),
    ),
  ];

  // Returns to the unzoomed page and keeps the line at the top of the view.
  void fitWidth() {
    final scale = transform.value.getMaxScaleOnAxis();
    final top = scroll.offset - transform.value.getTranslation().y / scale;
    transform.value = Matrix4.identity();
    scroll.jumpTo(top.clamp(0.0, scroll.position.maxScrollExtent));
  }

  Future<void> goToPage() async {
    final count = widget.note.document.pageCount();
    final text = TextEditingController(text: '${page + 1}');
    final chosen = await showCupertinoDialog<int>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Go to page'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: text,
            autofocus: true,
            placeholder: '1 to $count',
            keyboardType: TextInputType.number,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final number = int.tryParse(text.text);
              if (number != null && number >= 1 && number <= count)
                Navigator.pop(context, number - 1);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    text.dispose();
    if (chosen != null) jump(chosen);
  }

  Future<void> customizeToolbar() => showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => CupertinoActionSheet(
        title: const Text('Customize toolbar'),
        message: Column(
          children: [
            for (final (kind, label, icon) in toolKinds)
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, textAlign: TextAlign.start)),
                  CupertinoSwitch(
                    value: !hiddenTools.contains(kind),
                    onChanged: (shown) {
                      update(() {});
                      setState(() {
                        if (shown)
                          hiddenTools.remove(kind);
                        else
                          hiddenTools.add(kind);
                      });
                      web.window.localStorage.setItem(
                        'hiddenTools',
                        hiddenTools.join(','),
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ),
    ),
  );

  Future<void> exportPdf() async {
    final layers = widget.note.document.layers().toDart;
    final included = {
      for (final layer in layers)
        if (!layer.hidden) layer.id,
    };
    final first = TextEditingController(text: '1');
    final last = TextEditingController(
      text: '${widget.note.document.pageCount()}',
    );
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final from = int.tryParse(first.text);
          final to = int.tryParse(last.text);
          final valid =
              from != null &&
              to != null &&
              from >= 1 &&
              to >= from &&
              to <= widget.note.document.pageCount();
          return CupertinoAlertDialog(
            title: const Text('Export PDF'),
            content: Column(
              children: [
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: first,
                  placeholder: 'First page',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => update(() {}),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: last,
                  placeholder: 'Last page',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => update(() {}),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final layer in layers)
                          CupertinoListTile(
                            title: Text(layer.name),
                            trailing: CupertinoSwitch(
                              value: included.contains(layer.id),
                              onChanged: (value) => update(() {
                                if (value)
                                  included.add(layer.id);
                                else
                                  included.remove(layer.id);
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                onPressed: valid ? () => Navigator.pop(context, true) : null,
                child: const Text('Export'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted == true) {
      await widget.note.saver.save().toDart;
      final from = int.parse(first.text) - 1;
      native.host.exportPdf(
        widget.note,
        from,
        int.parse(last.text) - from,
        included.map((id) => id.toJS).toList().toJS,
      );
    }
    first.dispose();
    last.dispose();
  }

  void jump(int index) {
    if (drawing) return;
    final rect = widget.note.document.pageRect(index);
    scroll.animateTo(
      (rect.y * fit).clamp(0.0, scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void jumpToMark(native.NavigationMark mark) {
    final rect = widget.note.document.pageRect(mark.page);
    transform.value = Matrix4.identity();
    scroll.animateTo(
      ((rect.y + mark.y) * fit - 48).clamp(
        0.0,
        scroll.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void receiveDestination() {
    final destination = widget.destination.value;
    if (destination == null ||
        destination.noteKey != native.pathKey(widget.note.path))
      return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final marks = widget.note.document.navigation().toDart;
      for (final mark in marks) {
        if (mark.file == destination.file &&
            mark.id == destination.id &&
            mark.href.isEmpty) {
          jumpToMark(mark);
          return;
        }
      }
      setState(() => failure = 'The link destination is not in this notebook.');
    });
  }

  Future<void> bookmarks() async {
    final mark = await chooseDestination(context, widget.note.document);
    if (mark != null && mounted) jumpToMark(mark);
  }

  Future<void> linkSelection() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Link selected content'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'page'),
            child: const Text('Page or bookmark'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'note'),
            child: const Text('Another notebook'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'url'),
            child: const Text('URL or relative notebook path'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    String? href;
    if (action == 'page') {
      final mark = await chooseDestination(context, widget.note.document);
      if (mark != null)
        href =
            '${Uri(pathSegments: mark.file.split('/').skip(1)).toString()}${mark.id.isEmpty ? '' : '#${mark.id}'}';
    } else if (action == 'note') {
      href = await widget.onChooseNotebookLink(selection!.page);
    } else {
      final text = TextEditingController();
      href = await showCupertinoDialog<String>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Link destination'),
          content: CupertinoTextField(
            controller: text,
            autofocus: true,
            placeholder: 'https://… or ../../Note/pages/0001.svg',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, text.text.trim()),
              child: const Text('Link'),
            ),
          ],
        ),
      );
      text.dispose();
    }
    if (href != null && href.isNotEmpty)
      edit(() => canvas!.linkSelection(href!));
  }

  Future<void> followAt(Offset position) async {
    if (tool != 'navigate' || drawing || canvas == null) return;
    final p = canvas!.pageAt(position.dx, position.dy);
    if (p < 0) return;
    final rect = widget.note.document.pageRect(p);
    final matrix = transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final x = (position.dx - matrix.storage[12]) / (fit * scale) - rect.x;
    final y =
        (position.dy - matrix.storage[13] + scroll.offset * scale) /
            (fit * scale) -
        rect.y;
    for (final mark in widget.note.document.navigation().toDart.reversed) {
      if (mark.page == p &&
          mark.href.isNotEmpty &&
          x >= mark.x &&
          x <= mark.x + mark.width &&
          y >= mark.y &&
          y <= mark.y + mark.height) {
        await widget.onFollowLink(mark.href, p);
        return;
      }
    }
  }

  @override
  void dispose() {
    widget.destination.removeListener(receiveDestination);
    widget.viewport.removeListener(receiveViewport);
    pullTimer?.cancel();
    focus.dispose();
    figureText.dispose();
    ticker.dispose();
    widget.note.saver.removeEventListener('change', saveListener);
    scroll.dispose();
    transform.dispose();
    canvas?.free();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => run(
        () async {
          if (drawing) throw StateError('Complete the drawing before saving.');
          await widget.note.saver.save().toDart;
        },
      ),
      const SingleActivator(LogicalKeyboardKey.delete): () {
        if (selection != null) edit(() => canvas!.deleteSelection());
      },
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
        if (selection != null) edit(() => canvas!.duplicateSelection());
      },
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          history(false),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () =>
          history(true),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          history(true),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
          canvas?.selectAll(page),
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
          run(() => copy(false)),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true): () =>
          run(() => copy(true)),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
          run(paste),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          canvas?.clearSelection(),
    },
    child: Focus(
      focusNode: focus,
      autofocus: true,
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: Semantics(
            label: 'Library',
            button: true,
            excludeSemantics: true,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => run(widget.onLibrary),
              child: const Icon(LucideIcons.chevronLeft),
            ),
          ),
          middle: Text(widget.note.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                role: SemanticsRole.status,
                liveRegion: true,
                label: 'Notebook save',
                child: Text(saveLabel),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: drawing
                    ? null
                    : () => run(() async {
                        await widget.note.saver.save().toDart;
                      }),
                child: Text(
                  widget.note.saver.state.status == 'error'
                      ? 'Retry save'
                      : 'Save',
                ),
              ),
              menuButton('Pages', LucideIcons.layoutGrid, pagesMenu),
              menuButton('View', LucideIcons.layoutPanelLeft, viewMenu),
              menuButton('More', LucideIcons.circleEllipsis, moreMenu),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (failure != null || widget.note.saver.state.message != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      failure ?? widget.note.saver.state.message!,
                      style: const TextStyle(
                        color: CupertinoColors.destructiveRed,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (!toolbarRight) Center(child: toolbar()),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          width = constraints.maxWidth;
                          height = constraints.maxHeight;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) updateView();
                          });
                          return DragTarget<SelectionTransfer>(
                            onWillAcceptWithDetails: (_) =>
                                !drawing && canvas != null,
                            onAcceptWithDetails: (details) {
                              final box =
                                  context.findRenderObject()! as RenderBox;
                              final point = box.globalToLocal(details.offset);
                              unawaited(
                                run(() async {
                                  final svg = await details.data.read();
                                  if (svg.isNotEmpty)
                                    edit(
                                      () => canvas!.paste(
                                        svg,
                                        point.dx,
                                        point.dy,
                                        true,
                                      ),
                                    );
                                }),
                              );
                            },
                            builder: (context, candidates, rejected) => ClipRect(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: HtmlElementView(
                                        viewType: viewType,
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Listener(
                                      behavior: HitTestBehavior.opaque,
                                      onPointerDown: input,
                                      onPointerMove: input,
                                      onPointerUp: input,
                                      onPointerCancel: input,
                                      child: GestureDetector(
                                        onTapUp: tool == 'navigate'
                                            ? (details) => run(
                                                () => followAt(
                                                  details.localPosition,
                                                ),
                                              )
                                            : tool == 'bookmark'
                                            ? (details) => edit(
                                                () => canvas!.addBookmark(
                                                  details.localPosition.dx,
                                                  details.localPosition.dy,
                                                ),
                                              )
                                            : tool == 'text'
                                            ? (details) => run(
                                                () => textAt(
                                                  details.localPosition,
                                                ),
                                              )
                                            : null,
                                        child: InteractiveViewer(
                                          transformationController: transform,
                                          minScale: 1,
                                          maxScale: 5,
                                          panEnabled: !fingerDraws,
                                          onInteractionUpdate: fingerDraws
                                              ? fingerPan
                                              : null,
                                          child: ScrollConfiguration(
                                            behavior:
                                                const CupertinoScrollBehavior()
                                                    .copyWith(
                                                      dragDevices: {
                                                        if (!fingerDraws)
                                                          PointerDeviceKind
                                                              .touch,
                                                        PointerDeviceKind
                                                            .trackpad,
                                                      },
                                                    ),
                                            child: RawGestureDetector(
                                              gestures: {
                                                if (tool != 'navigate' &&
                                                    tool != 'text' &&
                                                    tool != 'bookmark')
                                                  EagerGestureRecognizer:
                                                      GestureRecognizerFactoryWithHandlers<
                                                        EagerGestureRecognizer
                                                      >(
                                                        () => EagerGestureRecognizer(
                                                          supportedDevices: {
                                                            PointerDeviceKind
                                                                .stylus,
                                                            PointerDeviceKind
                                                                .invertedStylus,
                                                          },
                                                        ),
                                                        (instance) {},
                                                      ),
                                                if (tool != 'navigate' &&
                                                    tool != 'text' &&
                                                    tool != 'bookmark')
                                                  PalmRejection:
                                                      GestureRecognizerFactoryWithHandlers<
                                                        PalmRejection
                                                      >(
                                                        () => PalmRejection(
                                                          () => strokes
                                                              .isNotEmpty,
                                                        ),
                                                        (instance) {},
                                                      ),
                                              },
                                              child: SingleChildScrollView(
                                                controller: scroll,
                                                physics:
                                                    const BouncingScrollPhysics(
                                                      parent:
                                                          AlwaysScrollableScrollPhysics(),
                                                    ),
                                                child: SizedBox(
                                                  width: width,
                                                  height:
                                                      widget.note.document
                                                          .contentSize()
                                                          .height *
                                                      fit,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (atEnd)
                                    Positioned(
                                      bottom: 12,
                                      left: 0,
                                      right: 0,
                                      child: IgnorePointer(
                                        child: Center(
                                          child: Semantics(
                                            container: true,
                                            child: Text(
                                              pullReady
                                                  ? 'Release to add a page'
                                                  : pullTimer != null
                                                  ? 'Hold to add a page'
                                                  : 'Pull and hold to add a page',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ...overlays(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (toolbarRight) Center(child: toolbar()),
                    if (clippingsOpen)
                      SizedBox(
                        width: 240,
                        child: DragTarget<SelectionTransfer>(
                          onWillAcceptWithDetails: (_) => !drawing,
                          onAcceptWithDetails: (details) => run(() async {
                            await native.host
                                .saveClipping(
                                  widget.engine,
                                  widget.note.root,
                                  await details.data.read(),
                                )
                                .toDart;
                            await refreshClippings();
                          }),
                          builder: (context, candidates, rejected) => ColoredBox(
                            color: candidates.isEmpty
                                ? CupertinoColors.systemGrey6.resolveFrom(
                                    context,
                                  )
                                : selectedFill,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text('Clippings'),
                                      ),
                                    ),
                                    CupertinoButton(
                                      onPressed: () => run(refreshClippings),
                                      child: const Icon(CupertinoIcons.refresh),
                                    ),
                                    CupertinoButton(
                                      onPressed: () =>
                                          setState(() => clippingsOpen = false),
                                      child: const Icon(CupertinoIcons.xmark),
                                    ),
                                  ],
                                ),
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Drop a selection here to save it. Drag a clipping onto the page.',
                                  ),
                                ),
                                if (selection != null && !drawing)
                                  CupertinoButton(
                                    onPressed: () => run(() async {
                                      await native.host
                                          .saveClipping(
                                            widget.engine,
                                            widget.note.root,
                                            canvas!.copySelection(false),
                                          )
                                          .toDart;
                                      await refreshClippings();
                                    }),
                                    child: const Text('Save selected content'),
                                  ),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      for (final (i, item) in clippings.indexed)
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                            children: [
                                              LongPressDraggable<
                                                SelectionTransfer
                                              >(
                                                data: SelectionTransfer(
                                                  () => clippingSource(item),
                                                ),
                                                feedback: SizedBox(
                                                  width: 100,
                                                  height: 100,
                                                  child: Image.memory(
                                                    item.png.toDart,
                                                  ),
                                                ),
                                                child: CupertinoButton(
                                                  onPressed: drawing
                                                      ? null
                                                      : () => run(() async {
                                                          final svg =
                                                              await clippingSource(
                                                                item,
                                                              );
                                                          edit(
                                                            () => canvas!.paste(
                                                              svg,
                                                              width / 2,
                                                              height / 2,
                                                              true,
                                                            ),
                                                          );
                                                        }),
                                                  child: Image.memory(
                                                    item.png.toDart,
                                                    semanticLabel:
                                                        'Insert clipping ${i + 1}',
                                                  ),
                                                ),
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  for (final action in [
                                                    'up',
                                                    'down',
                                                    'delete',
                                                  ])
                                                    CupertinoButton(
                                                      onPressed:
                                                          (action == 'up' &&
                                                                  i == 0) ||
                                                              (action ==
                                                                      'down' &&
                                                                  i ==
                                                                      clippings
                                                                              .length -
                                                                          1)
                                                          ? null
                                                          : () => run(() async {
                                                              await native.host
                                                                  .changeClipping(
                                                                    widget
                                                                        .engine,
                                                                    widget
                                                                        .note
                                                                        .root,
                                                                    item.id,
                                                                    action,
                                                                  )
                                                                  .toDart;
                                                              await refreshClippings();
                                                            }),
                                                      child: Semantics(
                                                        label:
                                                            '$action clipping',
                                                        child: Icon(
                                                          switch (action) {
                                                            'up' =>
                                                              CupertinoIcons
                                                                  .arrow_up,
                                                            'down' =>
                                                              CupertinoIcons
                                                                  .arrow_down,
                                                            _ =>
                                                              CupertinoIcons
                                                                  .trash,
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (figureSource.isNotEmpty)
                      SizedBox(
                        width: 280,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'TikZ figure',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Expanded(
                                child: CupertinoTextField(
                                  controller: figureText,
                                  readOnly: true,
                                  maxLines: null,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                ),
                              ),
                              if (!drawing)
                                CupertinoButton(
                                  onPressed: () =>
                                      setState(() => figureSource = ''),
                                  child: const Text('Close figure preview'),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
