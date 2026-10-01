import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show SemanticsRole;
import 'dart:ui' as ui show Image;
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
import 'package:toastification/toastification.dart';
import 'package:web/web.dart' as web;

import '../../errors.dart';
import '../../host.dart' as native;
import '../../layers_sheet.dart';
import '../../pages_sheet.dart';
import '../../bookmarks_sheet.dart';
import '../../figure_editor.dart';
import '../../undo_dial.dart';
import '../../data/open_notes.dart';
import '../library/library_dialogs.dart' show paperLabels;
import '../modal.dart';
import '../settings_sheet.dart';
import '../theme.dart';
import 'editor_input.dart';
import 'editor_view_model.dart';
import 'tools_view_model.dart';

import 'package:provider/provider.dart';

part 'rail.dart';
part 'editor_popovers.dart';
part 'editor_dialogs.dart';
part 'clippings_panel.dart';
part 'figure_panel.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
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
    required this.workspaceMenu,
    required this.onOpenNote,
    required this.onClose,
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
  // The View menu entries that the workspace owns: the tab bar and the split.
  final List<PullDownMenuEntry> Function() workspaceMenu;
  final Future<void> Function() onOpenNote;
  final Future<void> Function() onClose;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  final scroll = ScrollController();
  final focus = FocusNode();
  bool applyingViewport = false;
  final transform = PageTransform();
  final element = web.HTMLCanvasElement();
  // A frame of the ink canvas as a Flutter image, shown over the canvas
  // while a route covers the editor. Flutter's BackdropFilter does not blur
  // a platform view on the web (flutter/flutter#143747): without the image,
  // the translucent Cupertino surfaces show the ink sharp.
  ui.Image? still;
  bool capturing = false;
  ModalRoute<Object?>? route;
  late final Ticker ticker;
  late final String viewType;
  EditorViewModel get editor => context.read<EditorViewModel>();
  ToolsViewModel get tools => context.read<ToolsViewModel>();
  native.Canvas? get canvas => editor.canvas;
  set canvas(native.Canvas? value) {
    editor.canvas = value;
    editor.changed();
  }

  native.PenFile? get pens => tools.pens;
  set pens(native.PenFile? value) => tools.pens = value;
  String get pen => tools.pen;
  set pen(String value) => tools.pen = value;
  native.ToolSettings get penTool => tools.penTool;
  List<int> get palette => tools.palette;
  int get eraser => tools.eraser;
  set eraser(int value) => tools.eraser = value;
  String get tool => tools.tool;
  set tool(String value) => tools.tool = value;
  bool get clippingsOpen => editor.clippingsOpen;
  set clippingsOpen(bool value) {
    editor.clippingsOpen = value;
    editor.changed();
  }

  List<native.Clipping> get clippings => editor.clippings;
  set clippings(List<native.Clipping> value) {
    editor.clippings = value;
    editor.changed();
  }

  bool get drawing => editor.drawing;
  set drawing(bool value) {
    editor.drawing = value;
    editor.changed();
  }

  TextEditingController get figureText => editor.figureText;
  String get figureSource => editor.figureSource;
  set figureSource(String value) => editor.figureSource = value;
  int get selector => tools.selector;
  set selector(int value) => tools.selector = value;
  int get spaceMode => tools.spaceMode;
  set spaceMode(int value) => tools.spaceMode = value;
  native.Selection? get selection => editor.selection;
  set selection(native.Selection? value) {
    editor.selection = value;
    editor.changed();
  }

  double width = 1;
  double height = 1;
  double pixelRatio = 0;
  int get page => editor.page;
  set page(int value) {
    editor.page = value;
    editor.changed();
  }

  final touches = <int>{};
  final strokes = <int>{};
  final palms = <int>{};
  final taps = FingerTap();
  bool get fingerDraws => tools.fingerDraws;
  set fingerDraws(bool value) => tools.fingerDraws = value;
  Set<String> get hiddenTools => tools.hiddenTools;
  // The touch that draws the stroke in progress.
  int? fingerStroke;
  Timer? pullTimer;
  bool pullReady = false;
  bool atEnd = false;
  static int nextView = 0;
  // The View menu's page layout for every notebook: 0 is vertical scroll, 1
  // is horizontal scroll, and 2 is two pages per row in vertical scroll.
  static final arrangement = ValueNotifier<int>(
    int.parse(web.window.localStorage.getItem('pageArrangement') ?? '0'),
  );

  bool get horizontal => arrangement.value == 1;
  // The desk shows around the pages (docs/specs/tablet-ui.md, "Pages in the
  // editor"): a margin in view pixels at zoom 1 that zooms with the pages.
  static const deskMargin = 16.0;
  // Horizontal scroll fits the page height to the view; the others fit the
  // content width. Both leave the desk margin on each side.
  double get fit {
    final content = widget.note.document.contentSize();
    return horizontal
        ? (height - 2 * deskMargin) / content.height
        : (width - 2 * deskMargin) / content.width;
  }

  String get saveLabel => drawing
      ? 'Drawing in progress'
      : switch (editor.saveStatus) {
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
    widget.note.document.setArrangement(arrangement.value);
    arrangement.addListener(arrange);
    scroll.addListener(updateView);
    transform.addListener(updateView);
    widget.viewport.addListener(receiveViewport);
    widget.destination.addListener(receiveDestination);
    ticker = createTicker((_) {
      final covered = !(route?.isCurrent ?? true);
      if (covered && still == null && !capturing) canvas?.invalidate();
      final drew = canvas?.render() ?? false;
      if (covered && drew) unawaited(run(capture));
      if (!covered && still != null) showStill(null);
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
        canvas = await native.host.mountCanvas(widget.note, element).toDart;
        updateView();
        receiveDestination();
        pens = await native.host
            .readPens(widget.note.root, widget.engine)
            .toDart;
        canvas!.setTool(penTool);
      }),
    );
  }

  @override
  void didUpdateWidget(EditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) focus.requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
  }

  // Reads the frame that the canvas drew in this task: the drawing buffer
  // holds it only until the browser presents it.
  Future<void> capture() async {
    capturing = true;
    try {
      final bitmap = await web.window.createImageBitmap(element).toDart;
      final image = await ui_web.createImageFromImageBitmap(bitmap);
      if (mounted && !route!.isCurrent) {
        showStill(image);
      } else {
        image.dispose();
      }
    } finally {
      capturing = false;
    }
  }

  void showStill(ui.Image? image) {
    final previous = still;
    setState(() => still = image);
    WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      showError(error, stack);
    }
  }

  // Lays the pages out again and returns to the top of the current page.
  void arrange() {
    widget.note.document.setArrangement(arrangement.value);
    final current = page;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      transform.value = Matrix4.identity();
      scroll.jumpTo(pageOffset(current));
    });
  }

  // The scroll offset that puts the start of page `index` at the view's edge.
  double pageOffset(int index) {
    final rect = widget.note.document.pageRect(index);
    return ((horizontal ? rect.x : rect.y) * fit).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
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
      matrix.storage[12] +
          deskMargin * scale -
          (horizontal ? offset * scale : 0),
      matrix.storage[13] +
          deskMargin * scale -
          (horizontal ? 0 : offset * scale),
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

  Future<void> copy(bool cut) async {
    final target = canvas;
    if (target == null) return;
    final svg = target.copySelection(false);
    if (svg.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: svg));
    if (cut) edit(() => target.deleteSelection());
  }

  // Pastes at `at` in the view, or at its center.
  Future<void> paste([Offset? at]) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final svg = data?.text;
    if (svg != null && svg.isNotEmpty)
      edit(() => canvas!.paste(svg, at?.dx ?? width / 2, at?.dy ?? height / 2));
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
    if (drawingTools.contains(value)) {
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

  // With finger drawing the scroll view ignores touch and InteractiveViewer
  // does not pan, so a one-finger stroke leaves the page still. Two fingers
  // move the page here; a pinch still zooms through InteractiveViewer.
  void fingerPan(ScaleUpdateDetails details) {
    if (details.pointerCount < 2 || details.scale != 1.0) return;
    final scale = transform.value.getMaxScaleOnAxis();
    final delta = details.focalPointDelta;
    final (across, along) = horizontal
        ? (delta.dy, delta.dx)
        : (delta.dx, delta.dy);
    final axis = horizontal ? 1 : 0;
    final shift = (transform.value.storage[12 + axis] + across).clamp(
      (horizontal ? height : width) * (1 - scale),
      0.0,
    );
    transform.value = transform.value.clone()..setEntry(axis, 3, shift);
    scroll.jumpTo(
      (scroll.offset - along / scale).clamp(
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
                color: surface1,
                borderRadius: BorderRadius.circular(20),
                boxShadow: floatingShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(mode, style: callout),
                  if (tool == 'bookmark' && !drawing)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Tap the line to mark.',
                        style: callout.copyWith(color: secondaryLabel),
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
                              color: label,
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
        child: statusLabel('${page + 1} / ${widget.note.document.pageCount()}'),
      ),
    ];
  }

  // A status text on the chrome color, legible over the paper.
  Widget statusLabel(String text) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: surface1,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Semantics(container: true, child: Text(text, style: callout)),
    ),
  );

  Widget selectionMenu() {
    final figure = !drawing && canvas!.selectedFigure().isNotEmpty;
    Widget action(String label, IconData icon, VoidCallback onPressed) =>
        toolButton(label, icon, onPressed: (_) => onPressed());
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: surface1,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        children: [
          LongPressDraggable<SelectionTransfer>(
            data: SelectionTransfer(() => canvas!.copySelection(false)),
            feedback: const DecoratedBox(
              decoration: BoxDecoration(
                color: surface3,
                boxShadow: floatingShadow,
              ),
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
                child: Icon(LucideIcons.grab, color: label),
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
    buttonBuilder: (context, showMenu) => MergeSemantics(
      child: Semantics(
        label: label,
        button: true,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: showMenu,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Icon(icon, size: 20),
                Text(label, style: callout.copyWith(color: accentText)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  // One menu per object (docs/specs/tablet-ui.md, Editor): the current page
  // and the page sequence. Delete page is the last group, alone.
  List<PullDownMenuEntry> pagesMenu() => [
    PullDownMenuItem(
      title: 'Page overview',
      enabled: !drawing,
      onTap: () => run(showPages),
    ),
    PullDownMenuItem(
      title: 'Go to page',
      enabled: !drawing,
      onTap: () => run(goToPage),
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
    const PullDownMenuDivider.large(),
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
      title: 'Paper for new pages',
      enabled: !drawing,
      onTap: () => run(paperMenu),
    ),
    const PullDownMenuDivider.large(),
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
      enabled: !drawing && canvas != null,
      onTap: () =>
          run(() => manageLayers(context, widget.note.document, canvas!, edit)),
    ),
    const PullDownMenuDivider.large(),
    PullDownMenuItem(
      title: 'Delete page',
      isDestructive: true,
      enabled: !drawing && widget.note.document.pageCount() > 1,
      onTap: deletePage,
    ),
  ];

  List<PullDownMenuEntry> viewMenu() => [
    PullDownMenuItem.selectable(
      title: horizontal ? 'Fit height' : 'Fit width',
      selected: transform.value.getMaxScaleOnAxis() == 1,
      onTap: fitWidth,
    ),
    const PullDownMenuDivider.large(),
    for (final (value, title) in const [
      (0, 'Vertical scroll'),
      (1, 'Horizontal scroll'),
      (2, 'Two pages'),
    ])
      PullDownMenuItem.selectable(
        title: title,
        selected: arrangement.value == value,
        onTap: () {
          web.window.localStorage.setItem('pageArrangement', '$value');
          arrangement.value = value;
        },
      ),
    const PullDownMenuDivider.large(),
    ...widget.workspaceMenu(),
  ];

  // The document: save, share, export, versions; then closing it and the app
  // settings.
  List<PullDownMenuEntry> moreMenu() => [
    PullDownMenuItem(
      title: widget.note.saver.state.status == 'error' ? 'Retry save' : 'Save',
      enabled: !drawing,
      onTap: () => run(() async {
        await widget.note.saver.save().toDart;
      }),
    ),
    PullDownMenuItem(
      title: 'Share',
      enabled: !drawing,
      onTap: () => run(() => exportPdf(share: true)),
    ),
    PullDownMenuItem(
      title: 'Export PDF',
      enabled: !drawing,
      onTap: () => run(() => exportPdf(share: false)),
    ),
    PullDownMenuItem(
      title: 'Compare versions',
      enabled: !drawing,
      onTap: () => run(widget.onConflicts),
    ),
    const PullDownMenuDivider.large(),
    PullDownMenuItem(
      title: 'Close note',
      enabled: !drawing,
      onTap: () => run(widget.onClose),
    ),
    PullDownMenuItem(
      title: 'Settings',
      onTap: () => run(
        () => showSettings(
          context,
          followsLinks: () => tool == 'navigate',
          onFollowLinks: (on) => chooseTool(on ? 'navigate' : pen),
        ),
      ),
    ),
  ];

  // The page context menu (docs/specs/tablet-ui.md, Editor): a long press or
  // a secondary click on the page pastes there.
  Future<void> pageMenu(Offset local, Offset global) => showPullDownMenu(
    context: context,
    position: Rect.fromCenter(center: global, width: 1, height: 1),
    items: [
      PullDownMenuItem(
        title: 'Paste',
        enabled: !drawing && canvas != null,
        onTap: () => run(() => paste(local)),
      ),
    ],
  );

  // Returns to the unzoomed page and keeps the line at the top of the view,
  // or in horizontal scroll the column at its left edge.
  void fitWidth() {
    final scale = transform.value.getMaxScaleOnAxis();
    final top =
        scroll.offset - transform.value.storage[horizontal ? 12 : 13] / scale;
    transform.value = Matrix4.identity();
    scroll.jumpTo(top.clamp(0.0, scroll.position.maxScrollExtent));
  }

  void jump(int index) {
    if (drawing) return;
    scroll.animateTo(
      pageOffset(index),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void jumpToMark(native.NavigationMark mark) {
    final rect = widget.note.document.pageRect(mark.page);
    transform.value = Matrix4.identity();
    scroll.animateTo(
      ((horizontal ? rect.x + mark.x : rect.y + mark.y) * fit - 48).clamp(
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
      showError('The link destination is not in this notebook.');
    });
  }

  Future<void> followAt(Offset position) async {
    if (tool != 'navigate' || drawing || canvas == null) return;
    final p = canvas!.pageAt(position.dx, position.dy);
    if (p < 0) return;
    final rect = widget.note.document.pageRect(p);
    final matrix = transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final along = scroll.offset * scale;
    final x =
        (position.dx -
                matrix.storage[12] -
                deskMargin * scale +
                (horizontal ? along : 0)) /
            (fit * scale) -
        rect.x;
    final y =
        (position.dy -
                matrix.storage[13] -
                deskMargin * scale +
                (horizontal ? 0 : along)) /
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
    arrangement.removeListener(arrange);
    pullTimer?.cancel();
    focus.dispose();
    ticker.dispose();
    still?.dispose();
    scroll.dispose();
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<EditorViewModel>();
    context.watch<ToolsViewModel>();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            run(() async {
              if (drawing)
                throw StateError('Complete the drawing before saving.');
              await widget.note.saver.save().toDart;
            }),
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
            leading: MergeSemantics(
              child: Semantics(
                label: 'Library',
                button: true,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => run(widget.onLibrary),
                  child: const Icon(LucideIcons.chevronLeft),
                ),
              ),
            ),
            middle: Text(widget.note.name),
            trailing: FocusTraversalGroup(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    role: SemanticsRole.status,
                    liveRegion: true,
                    label: 'Notebook save',
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        saveLabel,
                        style: footnote.copyWith(color: secondaryLabel),
                      ),
                    ),
                  ),
                  MergeSemantics(
                    child: Semantics(
                      label: 'Open note',
                      button: true,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        onPressed: () => run(widget.onOpenNote),
                        child: const Icon(LucideIcons.filePlus2, size: 20),
                      ),
                    ),
                  ),
                  menuButton('Pages', LucideIcons.layoutGrid, pagesMenu),
                  menuButton('View', LucideIcons.layoutPanelLeft, viewMenu),
                  menuButton('More', LucideIcons.circleEllipsis, moreMenu),
                ],
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                if (widget.note.saver.state.message != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        widget.note.saver.state.message!,
                        style: callout.copyWith(color: destructive),
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      FocusTraversalGroup(child: rail()),
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
                                    // Always a child: a child that comes and
                                    // goes moves the listener to another
                                    // slot, and Flutter then rebuilds it and
                                    // the scroll view in it from scratch.
                                    Positioned.fill(
                                      child: RawImage(
                                        image: still,
                                        fit: BoxFit.fill,
                                        filterQuality: FilterQuality.none,
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Listener(
                                        behavior: HitTestBehavior.opaque,
                                        onPointerDown: input,
                                        onPointerMove: input,
                                        onPointerUp: input,
                                        onPointerCancel: input,
                                        // A signal reaches the listener in
                                        // the viewer, then the viewer, then
                                        // this listener.
                                        onPointerSignal: (event) =>
                                            transform.held = false,
                                        child: GestureDetector(
                                          onLongPressStart: fingerDraws
                                              ? null
                                              : (details) => run(
                                                  () => pageMenu(
                                                    details.localPosition,
                                                    details.globalPosition,
                                                  ),
                                                ),
                                          onSecondaryTapUp: (details) => run(
                                            () => pageMenu(
                                              details.localPosition,
                                              details.globalPosition,
                                            ),
                                          ),
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
                                            child: Listener(
                                              onPointerSignal: (event) =>
                                                  transform.held =
                                                      event
                                                          is PointerScrollEvent,
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
                                                    scrollDirection: horizontal
                                                        ? Axis.horizontal
                                                        : Axis.vertical,
                                                    physics:
                                                        const BouncingScrollPhysics(
                                                          parent:
                                                              AlwaysScrollableScrollPhysics(),
                                                        ),
                                                    child: SizedBox(
                                                      width: horizontal
                                                          ? widget.note.document
                                                                        .contentSize()
                                                                        .width *
                                                                    fit +
                                                                2 * deskMargin
                                                          : width,
                                                      height: horizontal
                                                          ? height
                                                          : widget.note.document
                                                                        .contentSize()
                                                                        .height *
                                                                    fit +
                                                                2 * deskMargin,
                                                    ),
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
                                        child: Center(
                                          child: statusLabel(
                                            pullReady
                                                ? 'Release to add a page'
                                                : pullTimer != null
                                                ? 'Hold to add a page'
                                                : 'Pull and hold to add a page',
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
                      if (clippingsOpen) clippingsPanel(),
                      if (figureSource.isNotEmpty) figurePanel(),
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
}
