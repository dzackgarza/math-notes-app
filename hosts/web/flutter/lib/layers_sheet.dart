import 'dart:js_interop';

import 'package:flutter/cupertino.dart';

import 'errors.dart';
import 'host.dart' as native;
import 'ui/theme.dart';

Future<void> manageLayers(
  BuildContext context,
  native.Document document,
  native.Canvas canvas,
  void Function(void Function()) edit,
) async {
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        final layers = document.layers().toDart;
        final active = canvas.activeLayer();
        void change(void Function() action) {
          try {
            edit(action);
            update(() {});
          } catch (error, stack) {
            showError(error, stack);
          }
        }

        Future<void> nameLayer(int? index) async {
          final name = TextEditingController(
            text: index == null ? '' : layers[index].name,
          );
          final accepted = await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: Text(index == null ? 'New layer' : 'Rename layer'),
              content: CupertinoTextField(
                controller: name,
                autofocus: true,
                placeholder: 'Layer name',
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (accepted == true)
            change(() {
              if (index == null) {
                document.addLayer(name.text.trim());
                canvas.setLayer(document.layers().toDart.length - 1);
              } else {
                final layer = layers[index];
                document.setLayer(
                  index,
                  name.text.trim(),
                  layer.hidden,
                  layer.locked,
                );
              }
            });
          name.dispose();
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: CupertinoPopupSurface(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Layers', style: title),
                          ),
                        ),
                        CupertinoButton(
                          onPressed: () => nameLayer(null),
                          child: const Text('Add'),
                        ),
                        CupertinoButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (var i = layers.length - 1; i >= 0; i--)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  CupertinoListTile(
                                    title: Text(layers[i].name),
                                    leading: Icon(
                                      active == i
                                          ? CupertinoIcons.checkmark_circle_fill
                                          : CupertinoIcons.circle,
                                    ),
                                    onTap: layers[i].hidden || layers[i].locked
                                        ? null
                                        : () =>
                                              change(() => canvas.setLayer(i)),
                                    trailing: CupertinoButton(
                                      onPressed: () => nameLayer(i),
                                      child: const Text('Rename'),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      CupertinoButton(
                                        onPressed: () => change(
                                          () => document.setLayer(
                                            i,
                                            layers[i].name,
                                            !layers[i].hidden,
                                            layers[i].locked,
                                          ),
                                        ),
                                        child: Text(
                                          layers[i].hidden ? 'Show' : 'Hide',
                                        ),
                                      ),
                                      CupertinoButton(
                                        onPressed: () => change(
                                          () => document.setLayer(
                                            i,
                                            layers[i].name,
                                            layers[i].hidden,
                                            !layers[i].locked,
                                          ),
                                        ),
                                        child: Text(
                                          layers[i].locked ? 'Unlock' : 'Lock',
                                        ),
                                      ),
                                      CupertinoButton(
                                        onPressed: i + 1 < layers.length
                                            ? () => change(
                                                () => document.moveLayer(
                                                  i,
                                                  i + 1,
                                                ),
                                              )
                                            : null,
                                        child: const Text('Up'),
                                      ),
                                      CupertinoButton(
                                        onPressed: i > 0
                                            ? () => change(
                                                () => document.moveLayer(
                                                  i,
                                                  i - 1,
                                                ),
                                              )
                                            : null,
                                        child: const Text('Down'),
                                      ),
                                      CupertinoButton(
                                        onPressed:
                                            i > 0 && !layers[i - 1].locked
                                            ? () => change(() {
                                                document.removeLayer(i, true);
                                                if (canvas.activeLayer() < 0)
                                                  canvas.setLayer(i - 1);
                                              })
                                            : null,
                                        child: const Text('Merge down'),
                                      ),
                                      CupertinoButton(
                                        onPressed: layers.length > 1
                                            ? () async {
                                                final remove = await showCupertinoDialog<bool>(
                                                  context: context,
                                                  builder: (context) =>
                                                      CupertinoAlertDialog(
                                                        title: Text(
                                                          'Delete ${layers[i].name}?',
                                                        ),
                                                        content: const Text(
                                                          'This removes its content from every page. Undo restores the layer.',
                                                        ),
                                                        actions: [
                                                          CupertinoDialogAction(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  false,
                                                                ),
                                                            child: const Text(
                                                              'Cancel',
                                                            ),
                                                          ),
                                                          CupertinoDialogAction(
                                                            isDestructiveAction:
                                                                true,
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  true,
                                                                ),
                                                            child: const Text(
                                                              'Delete',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                );
                                                if (remove == true)
                                                  change(() {
                                                    document.removeLayer(
                                                      i,
                                                      false,
                                                    );
                                                    if (canvas.activeLayer() <
                                                        0)
                                                      canvas.setLayer(
                                                        (i - 1).clamp(
                                                          0,
                                                          layers.length - 2,
                                                        ),
                                                      );
                                                  });
                                              }
                                            : null,
                                        child: const Text('Delete'),
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
        );
      },
    ),
  );
}
