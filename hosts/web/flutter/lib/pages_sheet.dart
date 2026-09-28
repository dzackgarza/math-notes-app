import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:reorderable_grid/reorderable_grid.dart';

import 'host.dart' as native;

/// The notebook's pages as a thumbnail grid. A long press drags a page to a
/// new position; each page's menu duplicates or deletes it. Returns the page
/// the user tapped, or null.
Future<int?> overviewPages(
  BuildContext context,
  native.Document document,
  int current,
  void Function(void Function()) edit,
) => showCupertinoModalPopup<int>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, update) {
      final count = document.pageCount();
      final thumbnails = [
        for (var index = 0; index < count; index++)
          document.pagePng(index, 240).toDart,
      ];
      void change(void Function() action) {
        edit(action);
        update(() {});
      }

      Future<void> pageActions(int index) async {
        final action = await showCupertinoModalPopup<String>(
          context: context,
          builder: (context) => CupertinoActionSheet(
            title: Text('Page ${index + 1}'),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, 'duplicate'),
                child: const Text('Duplicate'),
              ),
              if (count > 1)
                CupertinoActionSheetAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.pop(context, 'delete'),
                  child: const Text('Delete'),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        );
        switch (action) {
          case 'duplicate':
            change(() {
              document.duplicatePage(index);
              if (index < current) current++;
            });
          case 'delete':
            change(() {
              document.deletePage(index);
              if (index < current || current == count - 1) current--;
            });
        }
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
            child: CupertinoPopupSurface(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Pages'),
                      ),
                      const Spacer(),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ReorderableGrid(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            childAspectRatio: 0.62,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                      itemCount: count,
                      onReorder: (from, to) => change(() {
                        document.movePage(from, to);
                        if (current == from) {
                          current = to;
                        } else if (from < current && current <= to) {
                          current--;
                        } else if (to <= current && current < from) {
                          current++;
                        }
                      }),
                      itemBuilder: (context, index) =>
                          ReorderableGridDelayedDragStartListener(
                            key: ValueKey(index),
                            index: index,
                            child: Column(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    button: true,
                                    label: 'Page ${index + 1}',
                                    child: GestureDetector(
                                      onTap: () =>
                                          Navigator.pop(context, index),
                                      child: DecoratedBox(
                                        position: DecorationPosition.foreground,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: index == current
                                                ? CupertinoColors.activeBlue
                                                : CupertinoColors.systemGrey4,
                                            width: index == current ? 3 : 1,
                                          ),
                                        ),
                                        child: Image.memory(
                                          thumbnails[index],
                                          fit: BoxFit.contain,
                                          excludeFromSemantics: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('${index + 1}'),
                                    CupertinoButton(
                                      padding: const EdgeInsets.all(4),
                                      minimumSize: const Size.square(32),
                                      onPressed: () => pageActions(index),
                                      child: Icon(
                                        CupertinoIcons.ellipsis_circle,
                                        semanticLabel:
                                            'Page ${index + 1} actions',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
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
