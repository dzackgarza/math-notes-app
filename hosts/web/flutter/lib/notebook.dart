import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show SemanticsRole;
import 'dart:ui_web' as ui_web;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'host.dart' as native;
import 'layers_sheet.dart';
import 'pages_sheet.dart';
import 'bookmarks_sheet.dart';
import 'figure_editor.dart';

typedef NotebookViewport = ({double scale, double x, double y, double scroll});
typedef NoteDestination = ({String noteKey, String file, String id});

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
  List<native.Pen> pens = [];
  int pen = 0;
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
        pens =
            (await native.host.readPens(widget.note.root, widget.engine).toDart)
                .toDart;
        canvas = await native.host.mountCanvas(widget.note, element).toDart;
        canvas!.setTool(pens[pen].tool);
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
    if (tool == 'navigate' || tool == 'bookmark' || tool == 'text') return;
    if (target == null ||
        (event.kind != PointerDeviceKind.stylus &&
            event.kind != PointerDeviceKind.invertedStylus))
      return;
    if (native.host.acceptPen(
      target,
      element,
      event.timeStamp.inMicroseconds.toDouble(),
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

  void history(bool redo) {
    if (drawing) return;
    final step = redo
        ? widget.note.document.redo()
        : widget.note.document.undo();
    if (step == null) return;
    widget.note.saver.schedule();
    setState(
      () => page = step.page.clamp(0, widget.note.document.pageCount() - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) jump(page);
    });
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
    if (value == 'pen') canvas?.setTool(pens[pen].tool);
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
      chooseTool('pen');
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

  Future<void> paperMenu() async {
    final templates = await native.host.listTemplates(widget.note.root).toDart;
    if (!mounted) return;
    final chosen = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Paper'),
        actions: [
          for (final name in templates.toDart)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, name.toDart),
              child: Text(name.toDart),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (chosen == null) return;
    await native.host
        .applyTemplate(widget.note.root, widget.note.document, chosen)
        .toDart;
    widget.note.template = chosen;
    edit(() {});
  }

  Future<void> pageMenu() async {
    final count = widget.note.document.pageCount();
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('Page ${page + 1}'),
        actions: [
          for (final entry in {
            'before': 'Insert page before',
            'after': 'Insert page after',
            if (count > 1) 'delete': 'Delete page',
            if (page > 0) 'up': 'Move page up',
            if (page < count - 1) 'down': 'Move page down',
            'a4': 'Page size: A4',
            'letter': 'Page size: Letter',
          }.entries)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (action == null) return;
    edit(() {
      switch (action) {
        case 'before':
          widget.note.document.insertPage(page);
        case 'after':
          widget.note.document.insertPage(page + 1);
        case 'delete':
          widget.note.document.deletePage(page);
          page = page.clamp(0, widget.note.document.pageCount() - 1);
        case 'up':
          widget.note.document.movePage(page, page - 1);
          page--;
        case 'down':
          widget.note.document.movePage(page, page + 1);
          page++;
        case 'a4':
          widget.note.document.setPageSize(0);
        case 'letter':
          widget.note.document.setPageSize(1);
      }
    });
  }

  Future<void> showPages() async {
    final chosen = await overviewPages(
      context,
      widget.note.document,
      page,
      edit,
    );
    if (chosen != null) jump(chosen);
  }

  Future<void> zoomMenu() async {
    final scale = await showCupertinoModalPopup<double>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Zoom'),
        actions: [
          for (final value in [1.0, 1.5, 2.0, 3.0, 5.0])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, value),
              child: Text(
                value == 1 ? 'Fit width' : '${(value * 100).round()}%',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (scale != null)
      setState(
        () => transform.value = Matrix4.diagonal3Values(scale, scale, 1),
      );
  }

  Future<void> configurePen() async {
    if (pens.isEmpty) return;
    final original = pens[pen];
    var rgb = original.tool.rgb;
    var size = original.tool.size;
    var opacity = original.tool.opacity;
    var brush = original.tool.brush;
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CupertinoAlertDialog(
          title: Text(original.name),
          content: Column(
            children: [
              const SizedBox(height: 16),
              CupertinoSlidingSegmentedControl<int>(
                groupValue: brush,
                children: const {
                  0: Text('Pen'),
                  1: Text('Marker'),
                  2: Text('Highlight'),
                },
                onValueChanged: (value) {
                  if (value != null) update(() => brush = value);
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                children: [
                  for (final color in [
                    0x171717,
                    0x246BCE,
                    0xD92D39,
                    0x29955B,
                    0xFFCF26,
                    0x865AC2,
                  ])
                    Semantics(
                      label: 'Color ${color.toRadixString(16)}',
                      selected: rgb == color,
                      child: CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        onPressed: () => update(() => rgb = color),
                        child: Icon(
                          rgb == color
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle_fill,
                          color: Color(0xFF000000 | color),
                        ),
                      ),
                    ),
                ],
              ),
              Text('Width ${size.toStringAsFixed(1)} pt'),
              CupertinoSlider(
                value: size,
                min: 0.2,
                max: 20,
                divisions: 99,
                onChanged: (value) => update(() => size = value),
              ),
              Text('Opacity ${(opacity * 100).round()}%'),
              CupertinoSlider(
                value: opacity,
                min: 0.1,
                max: 1,
                divisions: 9,
                onChanged: (value) => update(() => opacity = value),
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    await updatePen(brush: brush, rgb: rgb, size: size, opacity: opacity);
  }

  // Replaces the selected preset in .pens.json; later strokes use it.
  Future<void> updatePen({
    required int brush,
    required int rgb,
    required double size,
    required double opacity,
  }) async {
    final original = pens[pen];
    final updated = native.Pen.create(
      id: original.id,
      name: original.name,
      tool: native.ToolSettings.create(
        brush: brush,
        rgb: rgb,
        size: size,
        opacity: opacity,
      ),
    );
    final next = [...pens]..[pen] = updated;
    await native.host
        .writePens(widget.note.root, widget.engine, next.toJS)
        .toDart;
    setState(() => pens = next);
    chooseTool('pen');
  }

  // The rail's swatches (docs/specs/tablet-ui.md, Editor): a color applies
  // to the selected pen preset.
  static const palette = [
    0x1A1A1A, 0x8E8E93, 0xFFFFFF, //
    0x1F4FB5, 0xD92D39, 0xF2842B, //
    0x29955B, 0x865AC2, 0xF4A6C0, //
    0xFFCF26, 0x3CBFAE, 0xC9A0F2, //
    0x0B2A5B, 0x8B5A2B, 0x2F9FE0, //
  ];

  Future<void> choosePenColor(int rgb) async {
    if (pens.isEmpty) return;
    final current = pens[pen].tool;
    await updatePen(
      brush: current.brush,
      rgb: rgb,
      size: current.size,
      opacity: current.opacity,
    );
  }

  Widget paletteGrid() {
    final current = pens.isEmpty ? null : pens[pen].tool.rgb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final color in palette)
            Semantics(
              label: 'Color #${color.toRadixString(16).padLeft(6, '0')}',
              selected: current == color,
              button: true,
              excludeSemantics: true,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: () => run(() => choosePenColor(color)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF000000 | color),
                    border: Border.all(
                      color: current == color
                          ? CupertinoColors.activeBlue
                          : CupertinoColors.systemGrey4,
                      width: current == color ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(36, 36),
            onPressed: () => run(configurePen),
            child: const Icon(
              CupertinoIcons.add_circled,
              size: 34,
              semanticLabel: 'Pen settings',
            ),
          ),
        ],
      ),
    );
  }

  // The later-phase tools, off the rail until their phase
  // (docs/plans/web-daily-notes-handoff.md, Delivery order).
  Future<void> moreTools() async {
    final actions = <(String, VoidCallback?)>[
      ('Pen settings', () => unawaited(run(configurePen))),
      ('Paste', () => unawaited(run(paste))),
      ('Select page', () => canvas?.selectAll(page)),
      (drawing ? 'Complete drawing' : 'Drawing mode', toggleDrawing),
      if (!drawing && canvas != null && canvas!.selectedFigure().isNotEmpty)
        (
          'Edit figure',
          () => unawaited(run(() => editFigure(canvas!.selectedFigure()))),
        ),
      (
        'Text',
        () {
          chooseTool('text');
          unawaited(textAt(Offset(width / 2, height / 2)));
        },
      ),
      (
        'Image',
        () => unawaited(
          run(() async {
            final inserted = await native.host
                .insertImage(widget.note, canvas!, page, width / 2, height / 2)
                .toDart;
            if (inserted.toDart) widget.note.saver.schedule();
          }),
        ),
      ),
      ('Insert space', drawing ? null : () => chooseTool('space')),
      (
        'Compare versions',
        drawing ? null : () => unawaited(run(widget.onConflicts)),
      ),
      (
        'Layers: $layerLabel',
        drawing || canvas == null
            ? null
            : () => unawaited(
                run(
                  () => manageLayers(
                    context,
                    widget.note.document,
                    canvas!,
                    edit,
                  ),
                ),
              ),
      ),
      (
        'Clippings',
        () => unawaited(
          run(() async {
            if (!clippingsOpen) await refreshClippings();
            setState(() => clippingsOpen = !clippingsOpen);
          }),
        ),
      ),
      ('Bookmarks', () => unawaited(run(bookmarks))),
      (
        'Add bookmark',
        drawing
            ? null
            : () {
                if (selection != null)
                  edit(() => canvas!.bookmarkSelection());
                else
                  chooseTool('bookmark');
              },
      ),
      ('Follow links', () => chooseTool('navigate')),
      if (selection != null) ...[
        (
          'Remove bookmark or link',
          () => edit(() => canvas!.ungroupSelection()),
        ),
        ('Link selected content', () => unawaited(run(linkSelection))),
      ],
    ];
    final chosen = await showCupertinoModalPopup<VoidCallback>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          for (final (label, action) in actions)
            CupertinoActionSheetAction(
              onPressed: action == null
                  ? () {}
                  : () => Navigator.pop(context, action),
              child: Text(
                label,
                style: action == null
                    ? const TextStyle(color: CupertinoColors.inactiveGray)
                    : null,
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    chosen?.call();
  }

  // A later-phase tool in use: its name, its mode, and the way back to the pen.
  List<Widget> activeTool() {
    final label = drawing
        ? 'Drawing mode'
        : switch (tool) {
            'space' => 'Insert space',
            'text' => 'Text',
            'bookmark' => 'Add bookmark',
            'navigate' => 'Follow links',
            _ => null,
          };
    if (label == null) return [];
    return [
      CupertinoListTile(
        title: Text(label),
        subtitle: tool == 'bookmark' && !drawing
            ? const Text('Tap the line to mark.')
            : null,
        backgroundColor: const Color(0xFFE3EBFC),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: drawing ? toggleDrawing : () => chooseTool('pen'),
          child: drawing
              ? const Text('Complete')
              : Semantics(
                  label: 'Close $label',
                  button: true,
                  excludeSemantics: true,
                  child: const Icon(CupertinoIcons.xmark_circle),
                ),
        ),
      ),
      if (tool == 'space' && !drawing)
        CupertinoSlidingSegmentedControl<int>(
          groupValue: spaceMode,
          children: const {
            4: Text('Vertical'),
            5: Text('Horizontal'),
            6: Text('Reflow'),
          },
          onValueChanged: (value) {
            if (value != null) {
              spaceMode = value;
              chooseTool('space');
            }
          },
        ),
    ];
  }

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
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => run(widget.onLibrary),
            child: const Text('Library'),
          ),
          middle: Text(widget.note.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: drawing ? null : () => run(exportPdf),
                child: const Text('Export PDF'),
              ),
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
                    SizedBox(
                      width: 170,
                      child: ListView(
                        children: [
                          for (var i = 0; i < pens.length; i++)
                            CupertinoListTile(
                              title: Text(pens[i].name),
                              subtitle: Text(
                                '${pens[i].tool.size.toStringAsFixed(1)} pt',
                              ),
                              leading: Icon(
                                CupertinoIcons.pencil,
                                color: Color(0xFF000000 | pens[i].tool.rgb),
                              ),
                              backgroundColor: tool == 'pen' && pen == i
                                  ? const Color(0xFFE3EBFC)
                                  : null,
                              onTap: () {
                                if (tool == 'pen' && pen == i) {
                                  unawaited(run(configurePen));
                                  return;
                                }
                                pen = i;
                                chooseTool('pen');
                              },
                            ),
                          CupertinoListTile(
                            title: const Text('Eraser'),
                            leading: const Icon(CupertinoIcons.clear),
                            onTap: () => chooseTool('eraser'),
                          ),
                          if (tool == 'eraser')
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: CupertinoSlidingSegmentedControl<int>(
                                groupValue: eraser,
                                children: const {
                                  0: Text('Stroke'),
                                  1: Text('Partial'),
                                  2: Text('Ruled'),
                                },
                                onValueChanged: (value) {
                                  if (value == null) return;
                                  eraser = value;
                                  chooseTool('eraser');
                                },
                              ),
                            ),
                          CupertinoListTile(
                            title: const Text('Lasso'),
                            leading: const Icon(
                              CupertinoIcons.selection_pin_in_out,
                            ),
                            onTap: () => chooseTool('lasso'),
                          ),
                          if (tool == 'lasso')
                            CupertinoSlidingSegmentedControl<int>(
                              groupValue: selector,
                              children: const {
                                0: Text('Freeform'),
                                1: Text('Rectangle'),
                                2: Text('Ruled'),
                              },
                              onValueChanged: (value) {
                                if (value != null) {
                                  selector = value;
                                  chooseTool('lasso');
                                }
                              },
                            ),
                          ...activeTool(),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            color: CupertinoColors.systemGrey5,
                          ),
                          paletteGrid(),
                          CupertinoListTile(
                            title: const Text('More'),
                            leading: const Icon(CupertinoIcons.ellipsis_circle),
                            onTap: () => run(moreTools),
                          ),
                          if (selection != null) ...[
                            LongPressDraggable<SelectionTransfer>(
                              data: SelectionTransfer(
                                () => canvas!.copySelection(false),
                              ),
                              feedback: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemGrey5,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('Copy selection'),
                                ),
                              ),
                              child: const CupertinoListTile(
                                title: Text('Drag a copy'),
                                leading: Icon(CupertinoIcons.hand_draw),
                              ),
                            ),
                            CupertinoListTile(
                              title: const Text('Copy'),
                              onTap: () => run(() => copy(false)),
                            ),
                            CupertinoListTile(
                              title: const Text('Cut'),
                              onTap: () => run(() => copy(true)),
                            ),
                            CupertinoListTile(
                              title: const Text('Duplicate'),
                              onTap: () =>
                                  edit(() => canvas!.duplicateSelection()),
                            ),
                            CupertinoListTile(
                              title: const Text('Delete selection'),
                              onTap: () =>
                                  edit(() => canvas!.deleteSelection()),
                            ),
                            CupertinoListTile(
                              title: const Text('Clear selection'),
                              onTap: () => canvas!.clearSelection(),
                            ),
                          ],
                        ],
                      ),
                    ),
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
                                          child: ScrollConfiguration(
                                            behavior:
                                                const CupertinoScrollBehavior()
                                                    .copyWith(
                                                      dragDevices: {
                                                        PointerDeviceKind.touch,
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
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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
                                ? CupertinoColors.systemGrey6
                                : const Color(0xFFD8E8FF),
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
              Row(
                children: [
                  CupertinoButton(
                    onPressed: drawing ? null : addPage,
                    child: const Text('Add page'),
                  ),
                  CupertinoButton(
                    onPressed: drawing ? null : () => history(false),
                    child: const Text('Undo'),
                  ),
                  CupertinoButton(
                    onPressed: drawing ? null : () => history(true),
                    child: const Text('Redo'),
                  ),
                  CupertinoButton(
                    onPressed: zoomMenu,
                    child: Text(
                      '${(transform.value.getMaxScaleOnAxis() * 100).round()}%',
                    ),
                  ),
                  CupertinoButton(
                    onPressed: drawing ? null : () => run(paperMenu),
                    child: const Text('Paper'),
                  ),
                  CupertinoButton(
                    onPressed: drawing ? null : () => run(pageMenu),
                    child: const Text('Page'),
                  ),
                  CupertinoButton(
                    onPressed: drawing ? null : () => run(showPages),
                    child: const Text('Pages'),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    onPressed: page > 0 ? () => jump(page - 1) : null,
                    child: const Text('Previous'),
                  ),
                  Semantics(
                    container: true,
                    child: Text(
                      '${page + 1} / ${widget.note.document.pageCount()}',
                    ),
                  ),
                  CupertinoButton(
                    onPressed: page + 1 < widget.note.document.pageCount()
                        ? () => jump(page + 1)
                        : null,
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
