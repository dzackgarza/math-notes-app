part of 'editor_screen.dart';

extension _EditorDialogs on _EditorScreenState {
  Future<void> textAt(Offset point) async {
    final target = canvas;
    if (target == null) return;
    final existing = target.selectTextAt(point.dx, point.dy);
    final properties = existing ? target.textProperties() : null;
    var rtl = properties?.rtl ?? false;
    final boxWidth = TextEditingController(
      text: (properties?.width ?? 300).toString(),
    );
    final controller = TextEditingController(text: properties?.content ?? '');
    String? validation;
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CupertinoAlertDialog(
          title: Text(existing ? 'Edit text' : 'Insert text'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: controller,
                  autofocus: true,
                  placeholder: 'Text',
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'NoteText',
                    fontFamilyFallback: [
                      'Noto Sans Arabic',
                      'Noto Sans Hebrew',
                      'Noto Sans Devanagari',
                      'Noto Sans Symbols2',
                    ],
                    fontSize: 18,
                  ),
                  minLines: 3,
                  maxLines: 8,
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: boxWidth,
                  prefix: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Width (pt)'),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const Text('Use 0 for the full text width.'),
                if (validation != null)
                  Text(
                    validation!,
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
                Row(
                  children: [
                    const Expanded(child: Text('Right to left')),
                    CupertinoSwitch(
                      value: rtl,
                      onChanged: (value) => update(() => rtl = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                final width = double.tryParse(boxWidth.text);
                if (width == null ||
                    !width.isFinite ||
                    width < 0 ||
                    width > 100000) {
                  update(() => validation = 'Use a width from 0 to 100000 pt.');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && controller.text.isNotEmpty) {
      final width = double.parse(boxWidth.text);
      edit(
        () => target.editText(
          native.TextBoxProperties(
            content: controller.text,
            width: width,
            rtl: rtl,
          ),
          point.dx,
          point.dy,
          existing,
        ),
      );
    } else if (accepted == true && existing) {
      edit(() => target.deleteSelection());
    }
    controller.dispose();
    boxWidth.dispose();
  }

  // The paper of the page and the size of new pages.
  Future<void> paperMenu() async {
    final templates = await native.host.listTemplates(widget.note.root).toDart;
    if (!mounted) return;
    Future<void> applyTemplate(String name) async {
      await native.host
          .applyTemplate(widget.note.root, widget.note.document, name)
          .toDart;
      widget.note.template = name;
      edit(() {});
    }

    final chosen = await showCupertinoModalPopup<Future<void> Function()>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Paper for new pages'),
        message: Text('Current: ${widget.note.template}'),
        actions: [
          for (final name in templates.toDart)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.pop(context, () => applyTemplate(name.toDart)),
              child: Text(name.toDart),
            ),
          for (final (size, orientation, label) in const [
            (0, 0, 'A4 portrait'),
            (0, 1, 'A4 landscape'),
            (1, 0, 'Letter portrait'),
            (1, 1, 'Letter landscape'),
          ])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(
                context,
                () async => edit(
                  () => widget.note.document.setPageSize(size, orientation),
                ),
              ),
              child: Text(label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    await chosen?.call();
  }

  void insertPage(int at) => edit(() => widget.note.document.insertPage(at));

  void deletePage() => edit(() {
    widget.note.document.deletePage(page);
    page = page.clamp(0, widget.note.document.pageCount() - 1);
  });

  Future<void> showPages() async {
    final chosen = await overviewPages(
      context,
      widget.note.document,
      page,
      edit,
    );
    if (chosen != null) jump(chosen);
  }

  Future<void> goToPage() async {
    final count = widget.note.document.pageCount();
    final text = TextEditingController(text: '${page + 1}');
    final chosen = await showCupertinoDialog<int>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Go to page'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: text,
            autofocus: true,
            placeholder: '1 to $count',
            keyboardType: TextInputType.number,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final number = int.tryParse(text.text);
              if (number != null && number >= 1 && number <= count)
                Navigator.pop(context, number - 1);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    text.dispose();
    if (chosen != null) jump(chosen);
  }

  Future<void> customizeToolbar() => showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => CupertinoActionSheet(
        title: const Text('Customize toolbar'),
        message: Column(
          children: [
            for (final (kind, label, icon) in toolKinds)
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, textAlign: TextAlign.start)),
                  CupertinoSwitch(
                    value: !hiddenTools.contains(kind),
                    onChanged: (shown) {
                      update(() {});
                      tools.setToolVisible(kind, shown);
                    },
                  ),
                ],
              ),
          ],
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ),
    ),
  );

  // The page range and layers of a PDF, which goes to a download or to the
  // system share sheet.
  Future<void> exportPdf({required bool share}) async {
    final layers = widget.note.document.layers().toDart;
    final included = {
      for (final layer in layers)
        if (!layer.hidden) layer.id,
    };
    final first = TextEditingController(text: '1');
    final last = TextEditingController(
      text: '${widget.note.document.pageCount()}',
    );
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final from = int.tryParse(first.text);
          final to = int.tryParse(last.text);
          final valid =
              from != null &&
              to != null &&
              from >= 1 &&
              to >= from &&
              to <= widget.note.document.pageCount();
          return CupertinoAlertDialog(
            title: Text(share ? 'Share PDF' : 'Export PDF'),
            content: Column(
              children: [
                const SizedBox(height: 16),
                CupertinoTextField(
                  controller: first,
                  placeholder: 'First page',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => update(() {}),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: last,
                  placeholder: 'Last page',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => update(() {}),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final layer in layers)
                          CupertinoListTile(
                            title: Text(layer.name),
                            trailing: CupertinoSwitch(
                              value: included.contains(layer.id),
                              onChanged: (value) => update(() {
                                if (value)
                                  included.add(layer.id);
                                else
                                  included.remove(layer.id);
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                onPressed: valid ? () => Navigator.pop(context, true) : null,
                child: Text(share ? 'Share' : 'Export'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted == true) {
      await widget.note.saver.save().toDart;
      final from = int.parse(first.text) - 1;
      final count = int.parse(last.text) - from;
      final ids = included.map((id) => id.toJS).toList().toJS;
      first.dispose();
      last.dispose();
      if (share)
        await native.host.sharePdf(widget.note, from, count, ids).toDart;
      else
        native.host.exportPdf(widget.note, from, count, ids);
      return;
    }
    first.dispose();
    last.dispose();
  }

  Future<void> bookmarks() async {
    final mark = await chooseDestination(context, widget.note.document);
    if (mark != null && mounted) jumpToMark(mark);
  }

  Future<void> linkSelection() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Link selected content'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'page'),
            child: const Text('Page or bookmark'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'note'),
            child: const Text('Another notebook'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'url'),
            child: const Text('URL or relative notebook path'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    String? href;
    if (action == 'page') {
      final mark = await chooseDestination(context, widget.note.document);
      if (mark != null)
        href =
            '${Uri(pathSegments: mark.file.split('/').skip(1)).toString()}${mark.id.isEmpty ? '' : '#${mark.id}'}';
    } else if (action == 'note') {
      href = await widget.onChooseNotebookLink(selection!.page);
    } else {
      final text = TextEditingController();
      href = await showCupertinoDialog<String>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Link destination'),
          content: CupertinoTextField(
            controller: text,
            autofocus: true,
            placeholder: 'https://… or ../../Note/pages/0001.svg',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, text.text.trim()),
              child: const Text('Link'),
            ),
          ],
        ),
      );
      text.dispose();
    }
    if (href != null && href.isNotEmpty)
      edit(() => canvas!.linkSelection(href!));
  }
}
