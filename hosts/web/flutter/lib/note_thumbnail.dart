import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import 'errors.dart';
import 'host.dart' as native;
import 'ui/theme.dart';

class NoteThumbnail extends StatefulWidget {
  const NoteThumbnail({
    super.key,
    required this.engine,
    required this.root,
    required this.note,
  });
  final native.Engine engine;
  final native.Directory root;
  final native.Note note;

  @override
  State<NoteThumbnail> createState() => _NoteThumbnailState();
}

class _NoteThumbnailState extends State<NoteThumbnail> {
  late Future<Uint8List?> image;

  void load() {
    image = native.host
        .thumbnail(widget.engine, widget.root, widget.note)
        .toDart
        .then((bytes) => bytes?.toDart)
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
  void didUpdateWidget(NoteThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.modified != widget.note.modified ||
        native.pathKey(oldWidget.note.path) != native.pathKey(widget.note.path))
      load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: image,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Semantics(
          label: 'Thumbnail failed: ${snapshot.error}',
          child: const Icon(CupertinoIcons.exclamationmark_triangle),
        );
      if (snapshot.connectionState != ConnectionState.done)
        return const Center(child: CupertinoActivityIndicator());
      final bytes = snapshot.data;
      if (bytes == null) return const Icon(CupertinoIcons.doc);
      return Stack(
        alignment: Alignment.topRight,
        children: [
          Image.memory(
            bytes,
            fit: BoxFit.contain,
            semanticLabel: '${widget.note.name} first page',
          ),
          if (widget.note.conflicts > 0)
            Semantics(
              label: 'Conflicting versions',
              // The badge sits on the page image; the surface keeps the
              // warning color legible on paper.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: surface1,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: warning,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
