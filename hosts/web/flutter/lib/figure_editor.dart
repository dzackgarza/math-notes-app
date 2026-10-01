import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/cupertino.dart';
import 'package:web/web.dart' as web;

import 'errors.dart';
import 'host.dart' as native;
import 'ui/theme.dart';

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
    if (closing) return;
    setState(() => closing = true);
    try {
      if (editor.ready) await editor.save().toDart;
      if (!mounted) return;
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (error, stack) {
      showError(error, stack);
      if (mounted) setState(() => closing = false);
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
        // A disabled CupertinoButton still exposes an enabled tap action.
        trailing: Semantics(
          enabled: !closing,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: closing ? null : close,
            child: Text(closing ? 'Saving…' : 'Save and close'),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (editor.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  editor.error,
                  style: callout.copyWith(color: destructive),
                ),
              ),
            if (!editor.ready)
              const Padding(
                padding: EdgeInsets.all(8),
                child: CupertinoActivityIndicator(),
              ),
            Expanded(child: HtmlElementView(viewType: viewType)),
          ],
        ),
      ),
    ),
  );
}
