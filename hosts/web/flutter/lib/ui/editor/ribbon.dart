part of 'editor_screen.dart';

const ribbonHeight = 52.0;
const ribbonMargin = 12.0;

extension _EditorRibbon on _EditorScreenState {
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
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: onPressed == null ? null : () => onPressed(anchor),
        onLongPress: onLongPress,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? selectedFill : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
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

  Widget swatch(int index, int color) {
    final current = pens != null && penTool.rgb == color;
    return Builder(
      builder: (anchor) => Semantics(
        label: 'Color ${hex(color)}',
        selected: current,
        button: true,
        excludeSemantics: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(36, 44),
          onPressed: () => run(() => tapSwatch(anchor, index)),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF000000 | color),
              border: Border.all(
                color: current ? label : separator,
                width: current ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The ribbon (docs/specs/tablet-ui.md, Editor): a rounded bar that floats
  // over the top or bottom edge of the page. It holds the tools, a divider,
  // then undo, redo, saved pens, swatches, and the color list.
  // The page height that the ribbon covers at each edge.
  double get ribbonTopInset => ribbonBottom ? 0 : ribbonHeight + ribbonMargin;
  double get ribbonBottomInset =>
      ribbonBottom ? ribbonHeight + ribbonMargin : 0;

  Widget ribbon() => Container(
    height: ribbonHeight,
    decoration: BoxDecoration(
      color: surface1,
      borderRadius: BorderRadius.circular(ribbonHeight / 2),
      boxShadow: floatingShadow,
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (kind, label, icon) in toolKinds)
            if (!hiddenTools.contains(kind))
              toolButton(
                kind == 'drawing' && drawing ? 'Complete drawing' : label,
                icon,
                selected: kind == 'drawing' ? drawing : tool == kind,
                onPressed: canvas == null || (kind == 'space' && drawing)
                    ? null
                    : (anchor) => tapTool(kind, anchor),
              ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: separator,
          ),
          UndoDial(
            enabled: !drawing,
            pageAbove: ribbonBottom,
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
          for (final (i, saved) in savedPens.indexed)
            toolButton(
              'Saved pen ${saved.size.toStringAsFixed(1)} pt ${hex(saved.rgb)}',
              toolKinds[saved.brush].$3,
              color: Color(0xFF000000 | saved.rgb),
              onPressed: (_) => run(() => applySaved(saved)),
              onLongPress: () => run(() => savedPenMenu(i)),
            ),
          for (final (i, color) in palette.indexed) swatch(i, color),
          toolButton(
            'Edit colors',
            LucideIcons.plus,
            onPressed: pens == null
                ? null
                : (anchor) => run(() => editPalette(anchor)),
          ),
        ],
      ),
    ),
  );
}
