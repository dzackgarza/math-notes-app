part of 'editor_screen.dart';

extension _ClippingsPanel on _EditorScreenState {
  Widget clippingsPanel() => SizedBox(
    width: 240,
    child: DragTarget<SelectionTransfer>(
      onWillAcceptWithDetails: (_) => !drawing,
      onAcceptWithDetails: (details) => run(() async {
        await native.host
            .saveClipping(
              widget.engine,
              widget.note.root,
              await details.data.read(),
            )
            .toDart;
        await refreshClippings();
      }),
      builder: (context, candidates, rejected) => ColoredBox(
        color: candidates.isEmpty ? surface1 : selectedFill,
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Clippings'),
                  ),
                ),
                CupertinoButton(
                  onPressed: () => run(refreshClippings),
                  child: const Icon(CupertinoIcons.refresh),
                ),
                CupertinoButton(
                  onPressed: () => clippingsOpen = false,
                  child: const Icon(CupertinoIcons.xmark),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Drop a selection here to save it. Drag a clipping onto the page.',
              ),
            ),
            if (selection != null && !drawing)
              CupertinoButton(
                onPressed: () => run(() async {
                  await native.host
                      .saveClipping(
                        widget.engine,
                        widget.note.root,
                        canvas!.copySelection(false),
                      )
                      .toDart;
                  await refreshClippings();
                }),
                child: const Text('Save selected content'),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final (i, item) in clippings.indexed)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          LongPressDraggable<SelectionTransfer>(
                            data: SelectionTransfer(() => clippingSource(item)),
                            feedback: SizedBox(
                              width: 100,
                              height: 100,
                              child: Image.memory(item.png.toDart),
                            ),
                            child: CupertinoButton(
                              onPressed: drawing
                                  ? null
                                  : () => run(() async {
                                      final svg = await clippingSource(item);
                                      edit(
                                        () => canvas!.paste(
                                          svg,
                                          width / 2,
                                          height / 2,
                                          true,
                                        ),
                                      );
                                    }),
                              child: Image.memory(
                                item.png.toDart,
                                semanticLabel: 'Insert clipping ${i + 1}',
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final action in ['up', 'down', 'delete'])
                                CupertinoButton(
                                  onPressed:
                                      (action == 'up' && i == 0) ||
                                          (action == 'down' &&
                                              i == clippings.length - 1)
                                      ? null
                                      : () => run(() async {
                                          await native.host
                                              .changeClipping(
                                                widget.engine,
                                                widget.note.root,
                                                item.id,
                                                action,
                                              )
                                              .toDart;
                                          await refreshClippings();
                                        }),
                                  child: Semantics(
                                    label: '$action clipping',
                                    child: Icon(switch (action) {
                                      'up' => CupertinoIcons.arrow_up,
                                      'down' => CupertinoIcons.arrow_down,
                                      _ => CupertinoIcons.trash,
                                    }),
                                  ),
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
  );
}
