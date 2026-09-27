import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/cupertino.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:web/web.dart' as web;

import 'host.dart' as native;

class FigureEditor extends StatefulWidget {
  const FigureEditor({super.key, required this.note, required this.id});
  final native.OpenNote note;
  final String id;
  @override
  State<FigureEditor> createState() => _FigureEditorState();
}

class _FigureEditorState extends State<FigureEditor> {
  static int nextView = 0;
  final frame = web.HTMLIFrameElement();
  late final String viewType;
  late final native.FigureEditor editor;
  late final JSFunction listener;
  bool closing = false;
  bool allowPop = false;
  String? failure;

  @override
  void initState() {
    super.initState();
    viewType = 'figure-editor-${nextView++}';
    frame.style.width = '100%';
    frame.style.height = '100%';
    frame.style.border = '0';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (_) => frame);
    editor = native.host.mountFigureEditor(widget.note, widget.id, frame);
    listener = ((web.Event event) {
      if (mounted) setState(() {});
    }).toJS;
    editor.addEventListener('change', listener);
  }

  Future<void> close() async {
    if (closing || editor.compiling) return;
    setState(() {
      closing = true;
      failure = null;
    });
    try {
      if (editor.ready) await editor.save().toDart;
      if (!mounted) return;
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (error) {
      if (mounted)
        setState(() {
          failure = error.toString();
          closing = false;
        });
    }
  }

  Future<void> compile() async {
    setState(() => failure = null);
    try {
      await editor.compile().toDart;
    } catch (error) {
      if (mounted) setState(() => failure = error.toString());
    }
  }

  Future<void> preamble() async {
    try {
      final original =
          (await native.host.readFigurePreamble(widget.note.root).toDart)
              .toDart;
      if (!mounted) return;
      final text = TextEditingController(text: original);
      String? error;
      bool saving = false;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => PointerInterceptor(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 800,
                  maxHeight: 560,
                ),
                child: CupertinoPopupSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Project figure preamble'),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Packages, TikZ libraries, and macros shared by figures in this notes folder.',
                          ),
                        ),
                        Expanded(
                          child: CupertinoTextField(
                            controller: text,
                            expands: true,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        if (error != null)
                          Text(
                            error!,
                            style: const TextStyle(
                              color: CupertinoColors.systemRed,
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            CupertinoButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            CupertinoButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      update(() {
                                        saving = true;
                                        error = null;
                                      });
                                      try {
                                        await native.host
                                            .writeFigurePreamble(
                                              widget.note.root,
                                              text.text,
                                              original,
                                            )
                                            .toDart;
                                        if (context.mounted)
                                          Navigator.pop(context);
                                      } catch (problem) {
                                        update(() {
                                          error = problem.toString();
                                          saving = false;
                                        });
                                      }
                                    },
                              child: Text(saving ? 'Saving…' : 'Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      text.dispose();
    } catch (error) {
      if (mounted) setState(() => failure = error.toString());
    }
  }

  @override
  void dispose() {
    editor.removeEventListener('change', listener);
    editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(close());
    },
    child: CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        middle: const Text('Figure editor'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: editor.compiling || closing ? null : preamble,
          child: const Text('Preamble'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: closing || editor.compiling ? null : close,
          child: Text(closing ? 'Saving…' : 'Save and close'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (failure != null || editor.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  failure ?? editor.error,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ),
            if (!editor.ready)
              const Padding(
                padding: EdgeInsets.all(8),
                child: CupertinoActivityIndicator(),
              ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      editor.progress.isEmpty
                          ? 'Compile the source to update its page view.'
                          : editor.progress,
                    ),
                  ),
                  CupertinoButton(
                    onPressed: !editor.ready || editor.compiling || closing
                        ? null
                        : compile,
                    child: Text(
                      editor.compiling ? 'Compiling…' : 'Compile figure',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: HtmlElementView(viewType: viewType)),
          ],
        ),
      ),
    ),
  );
}
