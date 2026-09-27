import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
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
  String tool = 'pen';
  String? failure;
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
    ticker = createTicker((_) => canvas?.render())..start();
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
    if (native.host.acceptPen(
      target,
      element,
      event.timeStamp.inMicroseconds.toDouble(),
    ))
      widget.note.saver.schedule();
  }

  void edit(void Function() action) {
    action();
    widget.note.saver.schedule();
    setState(() {});
    updateView();
  }

  void chooseTool(String value) {
    setState(() => tool = value);
    canvas?.setEraser(0, value == 'eraser');
    canvas?.setSelector(0, value == 'lasso');
    if (value == 'pen') canvas?.setTool(pens[pen].tool);
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
          Semantics(
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
                          subtitle: Text('${pens[i].tool.size.toStringAsFixed(1)} pt'),
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
                        title: const Text('Eraser'),
                        leading: const Icon(CupertinoIcons.clear),
                        onTap: () => chooseTool('eraser'),
                      ),
                      CupertinoListTile(
                        title: const Text('Lasso'),
                        leading: const Icon(
                          CupertinoIcons.selection_pin_in_out,
                        ),
                        onTap: () => chooseTool('lasso'),
                      ),
                      CupertinoListTile(
                        title: const Text('Add page'),
                        leading: const Icon(CupertinoIcons.add),
                        onTap: () => edit(
                          () => widget.note.document.insertPage(
                            widget.note.document.pageCount(),
                          ),
                        ),
                      ),
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
