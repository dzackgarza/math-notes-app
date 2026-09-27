import 'dart:js_interop';

import 'package:flutter/cupertino.dart';

import 'host.dart' as native;

Future<String?> compareVersions(
  BuildContext context,
  native.NoteConflict conflict,
) async {
  final transform = TransformationController();
  Widget version(String title, JSUint8Array? image, String summary) => Expanded(
    child: Column(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(title)),
        Expanded(
          child: image == null
              ? SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(summary),
                  ),
                )
              : InteractiveViewer(
                  transformationController: transform,
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: Image.memory(image.toDart, fit: BoxFit.contain),
                  ),
                ),
        ),
      ],
    ),
  );
  final choice = await showCupertinoDialog<String>(
    context: context,
    builder: (context) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 740),
          child: CupertinoPopupSurface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${conflict.provider}: ${conflict.original}',
                    style: const TextStyle(fontSize: 20),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        version(
                          'Current file',
                          conflict.left,
                          conflict.leftSummary,
                        ),
                        version(
                          'Conflict copy',
                          conflict.right,
                          conflict.rightSummary,
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context, 'original'),
                        child: Text(
                          conflict.originalBytes == null
                              ? 'Keep deletion'
                              : 'Keep current file',
                        ),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context, 'copy'),
                        child: Text(
                          conflict.originalBytes == null
                              ? 'Restore conflict copy'
                              : 'Keep conflict copy',
                        ),
                      ),
                      if (conflict.page && conflict.originalBytes != null)
                        CupertinoButton.filled(
                          onPressed: () => Navigator.pop(context, 'both'),
                          child: const Text('Keep both pages'),
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
  );
  transform.dispose();
  return choice;
}
