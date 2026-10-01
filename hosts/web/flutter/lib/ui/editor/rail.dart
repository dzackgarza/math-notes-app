part of 'editor_screen.dart';

const railWidth = 60.0;

// The writing tools, the inserters, and history, in the rail's groups
// (docs/specs/tablet-ui.md, Editor).
const _railTools = ['pen', 'marker', 'highlighter', 'eraser', 'lasso'];
const _railInserters = ['text', 'image', 'space', 'drawing'];

extension _EditorRail on _EditorScreenState {
  Widget toolButton(
    String label,
    IconData icon, {
    bool selected = false,
    Color color = label,
    void Function(BuildContext anchor)? onPressed,
    VoidCallback? onLongPress,
  }) => Builder(
    builder: (anchor) => Semantics(
      label: label,
      selected: selected,
      button: true,
      enabled: onPressed != null,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onPressed == null ? null : () => onPressed(anchor),
        onLongPress: onLongPress,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? selectedFill : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: onPressed == null ? tertiaryLabel : color,
            size: 24,
          ),
        ),
      ),
    ),
  );

  // A tap on an unselected tool chooses it; a tap on the selected tool opens
  // its settings. Image, text, and drawing mode act at once.
  void tapTool(String kind, BuildContext anchor) {
    switch (kind) {
      case 'image':
        unawaited(
          run(() async {
            final inserted = await native.host
                .insertImage(widget.note, canvas!, page, width / 2, height / 2)
                .toDart;
            if (inserted.toDart) widget.note.saver.schedule();
          }),
        );
      case 'drawing':
        toggleDrawing();
      case 'text':
        chooseTool('text');
        unawaited(textAt(Offset(width / 2, height / 2)));
      case _ when tool != kind:
        chooseTool(kind);
      case 'pen' || 'marker' || 'highlighter':
        unawaited(run(() => configurePen(anchor)));
      default:
        unawaited(run(() => modePopover(kind, anchor)));
    }
  }

  Widget kindButton(String kind) {
    final (_, label, icon) = toolKinds.firstWhere((item) => item.$1 == kind);
    return toolButton(
      kind == 'drawing' && drawing ? 'Complete drawing' : label,
      icon,
      selected: kind == 'drawing' ? drawing : tool == kind,
      onPressed: canvas == null || (kind == 'space' && drawing)
          ? null
          : (anchor) => tapTool(kind, anchor),
    );
  }

  // The current color of the drawing tool; it opens the color popover.
  Widget colorDot() {
    final rgb = pens == null ? null : penTool.rgb;
    return Builder(
      builder: (anchor) => Semantics(
        label: 'Colors',
        value: rgb == null ? null : hex(rgb),
        button: true,
        enabled: rgb != null,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: rgb == null ? null : () => run(() => colorPopover(anchor)),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rgb == null ? surface3 : Color(0xFF000000 | rgb),
              border: Border.all(color: label, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget swatch(
    BuildContext popover,
    StateSetter update,
    int index,
    int color,
  ) {
    final current = penTool.rgb == color;
    return Builder(
      builder: (anchor) => Semantics(
        label: 'Color ${hex(color)}',
        selected: current,
        button: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: () => run(() async {
            await tapSwatch(popover, anchor, index);
            if (popover.mounted) update(() {});
          }),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF000000 | color),
              border: Border.all(
                color: current ? accentText : separator,
                width: current ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Noteful's color menu: the swatches, the saved pens, and the palette
  // editor.
  Future<void> colorPopover(BuildContext anchor) => popover(
    anchor,
    'Colors',
    300,
    (context, update) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final (i, color) in palette.indexed)
              swatch(context, update, i, color),
            toolButton(
              'Edit colors',
              LucideIcons.plus,
              onPressed: (anchor) => run(() async {
                await editPalette(anchor);
                if (context.mounted) update(() {});
              }),
            ),
          ],
        ),
        if (savedPens.isNotEmpty) ...[
          section('Saved pens'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (i, saved) in savedPens.indexed)
                toolButton(
                  'Saved pen ${saved.size.toStringAsFixed(1)} pt ${hex(saved.rgb)}',
                  toolKinds[saved.brush].$3,
                  color: Color(0xFF000000 | saved.rgb),
                  onPressed: (_) => run(() async {
                    Navigator.pop(context);
                    await applySaved(saved);
                  }),
                  onLongPress: () => run(() => savedPenMenu(i)),
                ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget railGap() => Container(
    width: 28,
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 8),
    color: separator,
  );

  // The rail on the left edge of the page area: tools, inserters, history,
  // and the current color. Popovers open to its right, over the page.
  Widget rail() => Container(
    width: railWidth,
    decoration: const BoxDecoration(
      color: surface1,
      border: Border(right: BorderSide(color: separator)),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        spacing: 8,
        children: [
          for (final kind in _railTools)
            if (!hiddenTools.contains(kind)) kindButton(kind),
          railGap(),
          for (final kind in _railInserters)
            if (!hiddenTools.contains(kind)) kindButton(kind),
          toolButton(
            'Clippings',
            LucideIcons.inbox,
            selected: clippingsOpen,
            onPressed: (_) => run(() async {
              if (!clippingsOpen) await refreshClippings();
              clippingsOpen = !clippingsOpen;
            }),
          ),
          railGap(),
          UndoDial(
            enabled: !drawing,
            onStep: (direction) => history(direction > 0),
            child: Semantics(
              label: 'Undo',
              button: true,
              enabled: !drawing,
              onTap: () => history(false),
              excludeSemantics: true,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  LucideIcons.undo2,
                  color: drawing ? tertiaryLabel : label,
                ),
              ),
            ),
          ),
          toolButton(
            'Redo',
            LucideIcons.redo2,
            onPressed: drawing ? null : (_) => history(true),
          ),
          railGap(),
          colorDot(),
        ],
      ),
    ),
  );
}
