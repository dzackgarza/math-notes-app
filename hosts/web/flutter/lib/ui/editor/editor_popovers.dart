part of 'editor_screen.dart';

extension _EditorPopovers on _EditorScreenState {
  // The popover beside a toolbar button: a floating card with a title. Ink
  // samples inside it sit on a paper inset.
  Future<void> popover(
    BuildContext anchor,
    String title,
    double width,
    Widget Function(BuildContext context, StateSetter update) content,
  ) async {
    await showPopover<void>(
      context: anchor,
      direction: PopoverDirection.right,
      width: width,
      backgroundColor: surface2,
      shadow: floatingShadow,
      barrierColor: const Color(0x00000000),
      barrierLabel: 'Close $title',
      bodyBuilder: (context) => DefaultTextStyle(
        style: body,
        child: StatefulBuilder(
          builder: (context, update) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: headline,
                ),
              ),
              Container(height: 1, color: separator),
              Padding(
                padding: const EdgeInsets.all(16),
                child: content(context, update),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A round icon choice with a caption, as in Noteful's pen type row.
  Widget choice(
    String caption,
    IconData icon,
    bool selected,
    VoidCallback onPressed,
  ) => Semantics(
    label: caption,
    button: true,
    selected: selected,
    excludeSemantics: true,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(64, 72),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? accent : surface3,
            ),
            child: Icon(icon, size: 22, color: selected ? onAccent : label),
          ),
          const SizedBox(height: 4),
          Text(caption, style: footnote.copyWith(color: secondaryLabel)),
        ],
      ),
    ),
  );

  Widget section(String label) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(label, style: footnote.copyWith(color: secondaryLabel)),
  );

  // The eraser, lasso, and insert space modes.
  Future<void> modePopover(String kind, BuildContext anchor) {
    final (title, modes, current) = switch (kind) {
      'eraser' => (
        'Eraser',
        const [
          (0, 'Stroke', LucideIcons.spline),
          (1, 'Partial', LucideIcons.eraser),
          (2, 'Ruled', LucideIcons.ruler),
        ],
        eraser,
      ),
      'lasso' => (
        'Lasso',
        const [
          (0, 'Freehand', LucideIcons.lasso),
          (1, 'Rectangle', LucideIcons.squareDashed),
          (7, 'Oval', LucideIcons.circleDashed),
          (2, 'Ruled', LucideIcons.ruler),
        ],
        selector,
      ),
      _ => (
        'Insert space',
        const [
          (4, 'Vertical', LucideIcons.moveVertical),
          (5, 'Horizontal', LucideIcons.moveHorizontal),
          (6, 'Reflow', LucideIcons.wrapText),
        ],
        spaceMode,
      ),
    };
    var value = current;
    return popover(
      anchor,
      title,
      modes.length * 72 + 32,
      (context, update) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (mode, label, icon) in modes)
            choice(label, icon, value == mode, () {
              update(() => value = mode);
              switch (kind) {
                case 'eraser':
                  eraser = mode;
                case 'lasso':
                  selector = mode;
                default:
                  spaceMode = mode;
              }
              chooseTool(kind);
            }),
        ],
      ),
    );
  }

  // Noteful's pen popover: a stroke sample, labeled size presets and a
  // slider, opacity on the Advanced tab, and Save. The popover edits the
  // selected drawing tool only; the change applies when it closes.
  Future<void> configurePen(BuildContext anchor) async {
    if (pens == null) return;
    final highlighter = pen == 'highlighter';
    final original = penTool;
    final brush = original.brush;
    var size = original.size;
    var opacity = original.opacity;
    final rgb = original.rgb;
    var advanced = false;
    var save = false;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    native.ToolSettings settings() => native.ToolSettings.create(
      brush: brush,
      rgb: rgb,
      size: size,
      opacity: opacity,
    );
    final label = toolKinds.firstWhere((kind) => kind.$1 == pen).$2;
    await popover(anchor, label, 340, (context, update) {
      final presets = switch (pen) {
        'highlighter' => const [4.8, 7.2, 9.6, 14.4, 19.2],
        'marker' => const [1.2, 1.8, 2.4, 3.6, 4.8],
        _ => const [0.6, 1.2, 1.8, 2.4, 3.6],
      };
      final opacityRow = Row(
        children: [
          Expanded(
            child: CupertinoSlider(
              value: opacity,
              min: 0.1,
              max: 1,
              divisions: 9,
              onChanged: (value) => update(() => opacity = value),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${(opacity * 100).round()}%',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.memory(
              native.host
                  .penPreview(
                    widget.engine,
                    settings(),
                    (288 * ratio).round(),
                    (64 * ratio).round(),
                    1.5 * ratio,
                  )
                  .toDart,
              width: 288,
              height: 64,
              gaplessPlayback: true,
              semanticLabel: 'Stroke sample',
            ),
          ),
          if (highlighter || !advanced) ...[
            section('Size'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (i, value) in presets.indexed)
                  Semantics(
                    label: '$value pt',
                    button: true,
                    selected: (size - value).abs() < 0.05,
                    excludeSemantics: true,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(56, 56),
                      onPressed: () => update(() => size = value),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (size - value).abs() < 0.05
                                ? accentText
                                : paperEdge,
                            width: 2,
                          ),
                          color: paper,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Container(
                              width: 3.0 + 4 * i,
                              height: 3.0 + 4 * i,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF000000 | rgb),
                              ),
                            ),
                            Text(
                              '$value pt',
                              style: footnote.copyWith(color: coverInk),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: CupertinoSlider(
                    value: size.clamp(0.2, 20),
                    min: 0.2,
                    max: 20,
                    divisions: 99,
                    onChanged: (value) => update(() => size = value),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${size.toStringAsFixed(1)} pt',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
          if (highlighter || advanced) ...[section('Opacity'), opacityRow],
          if (!highlighter) ...[
            const SizedBox(height: 12),
            CupertinoSlidingSegmentedControl<bool>(
              groupValue: advanced,
              children: {
                false: Semantics(
                  label: 'Settings',
                  child: const Icon(LucideIcons.pencil, size: 18),
                ),
                true: Semantics(
                  label: 'Advanced',
                  child: const Icon(LucideIcons.slidersHorizontal, size: 18),
                ),
              },
              onValueChanged: (value) => update(() => advanced = value!),
            ),
          ],
          CupertinoButton(
            onPressed: () {
              save = true;
              Navigator.pop(context);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.bookmarkPlus, size: 18),
                SizedBox(width: 6),
                Text('Save pen'),
              ],
            ),
          ),
        ],
      );
    });
    if (size != original.size || opacity != original.opacity) {
      await updatePen(settings());
    }
    if (save) await writePens(saved: [...savedPens, settings()]);
  }

  // Writes .pens.json with the given parts replaced. The editor takes the new
  // settings before the write: the host writes files in call order.
  Future<void> writePens({
    native.ToolSettings? pen,
    native.ToolSettings? marker,
    native.ToolSettings? highlighter,
    List<int>? palette,
    List<native.ToolSettings>? saved,
  }) async {
    final next = native.PenFile.create(
      pen: pen ?? pens!.pen,
      marker: marker ?? pens!.marker,
      highlighter: highlighter ?? pens!.highlighter,
      palette: [for (final color in palette ?? this.palette) color.toJS].toJS,
      saved: saved?.toJS ?? pens!.saved,
    );
    pens = next;
    await native.host.writePens(widget.note.root, widget.engine, next).toDart;
  }

  List<native.ToolSettings> get savedPens => pens?.saved.toDart ?? [];

  // Replaces the selected drawing tool's settings; the next stroke uses them,
  // also while the file write is still in progress.
  Future<void> updatePen(native.ToolSettings settings) async {
    final write = writePens(
      pen: pen == 'pen' ? settings : null,
      marker: pen == 'marker' ? settings : null,
      highlighter: pen == 'highlighter' ? settings : null,
    );
    chooseTool(pen);
    await write;
  }

  Future<void> choosePenColor(int rgb) async {
    if (pens == null) return;
    final current = penTool;
    await updatePen(
      native.ToolSettings.create(
        brush: current.brush,
        rgb: rgb,
        size: current.size,
        opacity: current.opacity,
      ),
    );
  }

  // A saved pen is a shortcut to the settings of the drawing tool of its brush.
  Future<void> applySaved(native.ToolSettings settings) async {
    pen = drawingTools[settings.brush];
    await updatePen(settings);
  }

  Future<void> savedPenMenu(int index) async {
    final remove = await showModalSheet<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove saved pen'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (remove == true) await writePens(saved: [...savedPens]..removeAt(index));
  }

  // A swatch recolors the selection when there is one. Otherwise it sets the
  // drawing tool's color, and a tap on the current color edits it. A choice
  // closes the color popover.
  Future<void> tapSwatch(
    BuildContext popover,
    BuildContext anchor,
    int index,
  ) async {
    final color = palette[index];
    if (selection != null) {
      Navigator.pop(popover);
      edit(() => canvas!.recolorSelection(color));
      return;
    }
    if (drawingTools.contains(tool) && penTool.rgb == color) {
      await editSwatch(anchor, index);
      return;
    }
    Navigator.pop(popover);
    await choosePenColor(color);
  }

  Widget colorWheel(int rgb, ValueChanged<int> changed) => Semantics(
    label: 'Color wheel',
    child: SizedBox(
      width: 228,
      height: 228,
      child: ColorWheelPicker(
        color: Color(0xFF000000 | rgb),
        onChanged: (color) => changed(color.toARGB32() & 0xFFFFFF),
        onWheel: (_) {},
        wheelWidth: 20,
      ),
    ),
  );

  Future<void> editSwatch(BuildContext anchor, int index) async {
    var rgb = palette[index];
    await popover(
      anchor,
      'Color',
      260,
      (context, update) =>
          Center(child: colorWheel(rgb, (next) => update(() => rgb = next))),
    );
    if (rgb == palette[index]) return;
    await writePens(palette: [...palette]..[index] = rgb);
    await choosePenColor(rgb);
  }

  Future<void> editPalette(BuildContext anchor) async {
    final colors = palette;
    var rgb = penTool.rgb;
    await popover(
      anchor,
      'Colors',
      280,
      (context, update) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (i, color) in colors.indexed)
                Semantics(
                  label: 'Remove color ${hex(color)}',
                  button: true,
                  excludeSemantics: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: () => update(() => colors.removeAt(i)),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF000000 | color),
                        border: Border.all(color: separator),
                      ),
                      child: const Icon(
                        LucideIcons.x,
                        size: 14,
                        color: onAccent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          colorWheel(rgb, (next) => update(() => rgb = next)),
          CupertinoButton(
            onPressed: () => update(() => colors.add(rgb)),
            child: const Text('Add color'),
          ),
        ],
      ),
    );
    if (!listEquals(colors, palette)) await writePens(palette: colors);
  }
}
