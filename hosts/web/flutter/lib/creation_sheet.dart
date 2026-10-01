import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/cupertino.dart';

import 'errors.dart';
import 'host.dart' as native;

class CreationSheet extends StatelessWidget {
  const CreationSheet({
    super.key,
    required this.title,
    required this.content,
    required this.preview,
    required this.actions,
  });

  final String title;
  final Widget content;
  final Widget preview;
  final List<Widget> actions;

  // The sheet is as tall as its content, up to the screen. A wide sheet puts
  // the preview beside the form; a narrow one puts it under the form.
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Semantics(
            role: SemanticsRole.dialog,
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: CupertinoPopupSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Semantics(
                      header: true,
                      child: DefaultTextStyle(
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .navTitleTextStyle,
                        child: Text(title),
                      ),
                    ),
                  ),
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final form = Padding(
                          padding: const EdgeInsets.all(20),
                          child: content,
                        );
                        final shown = Padding(
                          padding: const EdgeInsets.all(20),
                          child: SizedBox(height: 280, child: preview),
                        );
                        if (constraints.maxWidth < 600) {
                          return SingleChildScrollView(
                            child: Column(children: [form, shown]),
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: SingleChildScrollView(child: form)),
                            SizedBox(width: 260, child: shown),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PaperPreview extends StatefulWidget {
  const PaperPreview({
    super.key,
    required this.engine,
    required this.root,
    required this.paper,
    required this.size,
    required this.orientation,
  });
  final native.Engine engine;
  final native.Directory root;
  final String paper;
  final String size;
  final String orientation;

  @override
  State<PaperPreview> createState() => _PaperPreviewState();
}

class _PaperPreviewState extends State<PaperPreview> {
  late Future<Uint8List> image;

  void load() {
    image = native.host
        .paperPreview(
          widget.engine,
          widget.root,
          widget.paper,
          widget.size,
          widget.orientation,
        )
        .toDart
        .then((bytes) => bytes.toDart)
        .onError<Object>((error, stack) {
          showError(error, stack);
          Error.throwWithStackTrace(error, stack);
        });
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(PaperPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper != widget.paper ||
        oldWidget.size != widget.size ||
        oldWidget.orientation != widget.orientation)
      load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: image,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text('Preview failed: ${snapshot.error}');
      if (!snapshot.hasData)
        return const Center(child: CupertinoActivityIndicator());
      return Image.memory(
        snapshot.data!,
        fit: BoxFit.contain,
        semanticLabel: 'First page preview',
      );
    },
  );
}
