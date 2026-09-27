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

class Notebook extends StatefulWidget {
  const Notebook({
    super.key,
    required this.note,
    required this.engine,
    required this.onLibrary,
  });
  final native.OpenNote note;
  final native.Engine engine;
  final Future<void> Function() onLibrary;
  @override
  State<Notebook> createState() => _NotebookState();
}

class _NotebookState extends State<Notebook>
    with SingleTickerProviderStateMixin {
  final scroll = ScrollController();
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
  String? failure;
  native.Selection? selection;
  double width = 1;
  double height = 1;
  double pixelRatio = 0;
  int page = 0;
  static int nextView = 0;

  double get fit => width / widget.note.document.contentSize().width;
  String get saveLabel => switch (widget.note.saver.state.status) {
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
    ticker = createTicker((_) {
      canvas?.render();
      final next = canvas?.selection();
      if (next?.count != selection?.count ||
          next?.x != selection?.x ||
          next?.y != selection?.y ||
          next?.width != selection?.width ||
          next?.height != selection?.height) {
        setState(() => selection = next);
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
      }),
    );
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
  }

  void input(PointerEvent event) {
    final target = canvas;
    if (target == null ||
        (event.kind != PointerDeviceKind.stylus &&
            event.kind != PointerDeviceKind.invertedStylus))
      return;
    if (tool == 'text') {
      if (event is PointerDownEvent) {
        unawaited(textAt(event.localPosition));
      }
      return;
    }
    if (native.host.acceptPen(
      target,
      element,
      event.timeStamp.inMicroseconds.toDouble(),
    ))
      widget.note.saver.schedule();
  }

  Future<void> textAt(Offset point) async {
    final target = canvas;
    if (target == null) return;
    final existing = target.selectTextAt(point.dx, point.dy);
    final controller = TextEditingController(
      text: existing ? target.selectedText() : '',
    );
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(existing ? 'Edit text' : 'Insert text'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: 'Text',
            style: const TextStyle(fontFamily: 'NoteText', fontSize: 18),
            minLines: 3,
            maxLines: 8,
          ),
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
    );
    if (accepted == true && controller.text.isNotEmpty) {
      edit(
        () => existing
            ? target.setSelectedText(controller.text)
            : target.insertText(controller.text, point.dx, point.dy),
      );
    }
    controller.dispose();
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
    canvas?.setEraser(eraser, value == 'eraser');
    canvas?.setSelector(0, value == 'lasso');
    if (value == 'pen') canvas?.setTool(pens[pen].tool);
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

  Future<void> exportPdf() async {
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
      native.host.exportPdf(widget.note, from, int.parse(last.text) - from);
    }
    first.dispose();
    last.dispose();
  }

  void jump(int index) {
    final rect = widget.note.document.pageRect(index);
    scroll.animateTo(
      (rect.y * fit).clamp(0.0, scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    ticker.dispose();
    widget.note.saver.removeEventListener('change', saveListener);
    scroll.dispose();
    transform.dispose();
    canvas?.free();
    widget.note.document.free();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
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
            onPressed: () => run(exportPdf),
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
            onPressed: () => run(() async {
              await widget.note.saver.save().toDart;
            }),
            child: Text(
              widget.note.saver.state.status == 'error' ? 'Retry save' : 'Save',
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
                  style: const TextStyle(color: CupertinoColors.destructiveRed),
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
                            pen = i;
                            chooseTool('pen');
                          },
                        ),
                      CupertinoListTile(
                        title: const Text('Pen settings'),
                        leading: const Icon(CupertinoIcons.slider_horizontal_3),
                        onTap: () => run(configurePen),
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
                      CupertinoListTile(
                        title: const Text('Text'),
                        leading: const Icon(CupertinoIcons.textformat),
                        onTap: () {
                          chooseTool('text');
                          unawaited(textAt(Offset(width / 2, height / 2)));
                        },
                      ),
                      CupertinoListTile(
                        title: const Text('Image'),
                        leading: const Icon(CupertinoIcons.photo),
                        onTap: () => run(() async {
                          final inserted = await native.host
                              .insertImage(
                                widget.note,
                                canvas!,
                                page,
                                width / 2,
                                height / 2,
                              )
                              .toDart;
                          if (inserted.toDart) widget.note.saver.schedule();
                        }),
                      ),
                      CupertinoListTile(
                        title: const Text('Select page'),
                        leading: const Icon(
                          CupertinoIcons.selection_pin_in_out,
                        ),
                        onTap: () => canvas?.selectAll(page),
                      ),
                      CupertinoListTile(
                        title: const Text('Paste'),
                        leading: const Icon(CupertinoIcons.doc_on_clipboard),
                        onTap: () => run(paste),
                      ),
                      if (selection != null) ...[
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
                          onTap: () => edit(() => canvas!.duplicateSelection()),
                        ),
                        CupertinoListTile(
                          title: const Text('Delete selection'),
                          onTap: () => edit(() => canvas!.deleteSelection()),
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
                      return ClipRect(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: HtmlElementView(viewType: viewType),
                              ),
                            ),
                            Positioned.fill(
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: input,
                                onPointerMove: input,
                                onPointerUp: input,
                                onPointerCancel: input,
                                child: InteractiveViewer(
                                  transformationController: transform,
                                  minScale: 1,
                                  maxScale: 5,
                                  child: ScrollConfiguration(
                                    behavior: const CupertinoScrollBehavior()
                                        .copyWith(
                                          dragDevices: {
                                            PointerDeviceKind.touch,
                                            PointerDeviceKind.trackpad,
                                          },
                                        ),
                                    child: SingleChildScrollView(
                                      controller: scroll,
                                      physics: const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
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
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              CupertinoButton(
                onPressed: () => edit(
                  () => widget.note.document.insertPage(
                    widget.note.document.pageCount(),
                  ),
                ),
                child: const Text('Add page'),
              ),
              CupertinoButton(
                onPressed: () => edit(() {
                  widget.note.document.undo();
                }),
                child: const Text('Undo'),
              ),
              CupertinoButton(
                onPressed: () => edit(() {
                  widget.note.document.redo();
                }),
                child: const Text('Redo'),
              ),
              const Spacer(),
              CupertinoButton(
                onPressed: page > 0 ? () => jump(page - 1) : null,
                child: const Text('Previous'),
              ),
              Text('${page + 1} / ${widget.note.document.pageCount()}'),
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
  );
}
