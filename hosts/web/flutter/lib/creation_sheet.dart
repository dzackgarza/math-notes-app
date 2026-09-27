import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import 'host.dart' as native;

class CreationSheet extends StatelessWidget {
  const CreationSheet({
    super.key,
    required this.title,
    required this.content,
    required this.preview,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final Widget preview;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
          child: CupertinoPopupSurface(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Semantics(
                    header: true,
                    child: DefaultTextStyle(
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navTitleTextStyle,
                      child: title,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final form = Padding(
                        padding: const EdgeInsets.all(24),
                        child: content,
                      );
                      if (constraints.maxWidth < 640) {
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              form,
                              SizedBox(height: 260, child: preview),
                            ],
                          ),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: SingleChildScrollView(child: form)),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: preview,
                            ),
                          ),
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
  );
}

class PaperPreview extends StatefulWidget {
  const PaperPreview({
    super.key,
    required this.engine,
    required this.root,
    required this.paper,
    required this.size,
  });
  final native.Engine engine;
  final native.Directory root;
  final String paper;
  final String size;

  @override
  State<PaperPreview> createState() => _PaperPreviewState();
}

class _PaperPreviewState extends State<PaperPreview> {
  late Future<Uint8List> image;

  void load() {
    image = native.host
        .paperPreview(widget.engine, widget.root, widget.paper, widget.size)
        .toDart
        .then((bytes) => bytes.toDart);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(PaperPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper != widget.paper || oldWidget.size != widget.size)
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
