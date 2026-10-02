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
    final accepted = await showModalDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Alert(
          title: Text(existing ? 'Edit text' : 'Insert text'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Text', style: footnote.copyWith(color: secondaryLabel)),
                const SizedBox(height: 6),
                CupertinoTextField(
                  cursorOpacityAnimates: false,
                  decoration: fieldDecoration,
                  placeholderStyle: placeholderText,
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
                  cursorOpacityAnimates: false,
                  decoration: fieldDecoration,
                  placeholderStyle: placeholderText,
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
                    style: callout.copyWith(color: destructive),
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
            AlertAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            AlertAction(
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

  // The paper, size, and orientation of new pages. Each change applies at
  // once, as the toolbar sheet's switches do.
  Future<void> paperMenu() async {
    final templates =
        (await native.host.listTemplates(widget.note.root).toDart).toDart
            .map((name) => name.toDart)
            .toList()
          ..sort(
            (a, b) => (paperLabels[a] ?? a).compareTo(paperLabels[b] ?? b),
          );
    if (!mounted) return;
    Future<void> applyTemplate(String name) async {
      await native.host
          .applyTemplate(widget.note.root, widget.note.document, name)
          .toDart;
      widget.note.template = name;
      edit(() {});
    }

    Widget heading(String text) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: subhead),
      ),
    );
    await showModalSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final current = widget.note.document.pageSize();
          return ActionSheet(
            title: const Text('Paper for new pages'),
            message: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Paper style'),
                for (final name in templates)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 36),
                    onPressed: () => unawaited(
                      run(() async {
                        await applyTemplate(name);
                        update(() {});
                      }),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            paperLabels[name] ?? name,
                            textAlign: TextAlign.start,
                          ),
                        ),
                        if (name == widget.note.template)
                          const Icon(CupertinoIcons.checkmark, size: 18),
                      ],
                    ),
                  ),
                heading('Page size'),
                CupertinoSlidingSegmentedControl<int>(
                  backgroundColor: segmentTrack,
                  thumbColor: segmentThumb,
                  groupValue: current.size == 2 ? null : current.size,
                  children: const {
                    0: Text('A4', style: segmentLabel),
                    1: Text('Letter', style: segmentLabel),
                  },
                  onValueChanged: (size) {
                    if (size == null) return;
                    edit(
                      () => widget.note.document.setPageSize(
                        size,
                        current.orientation,
                      ),
                    );
                    update(() {});
                  },
                ),
                if (current.size == 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Custom: ${current.width.round()} × ${current.height.round()} pt',
                    ),
                  ),
                heading('Orientation'),
                CupertinoSlidingSegmentedControl<int>(
                  backgroundColor: segmentTrack,
                  thumbColor: segmentThumb,
                  groupValue: current.orientation,
                  children: const {
                    0: Text('Portrait', style: segmentLabel),
                    1: Text('Landscape', style: segmentLabel),
                  },
                  onValueChanged: (orientation) {
                    if (orientation == null) return;
                    edit(
                      () => widget.note.document.setPageSize(
                        current.size,
                        orientation,
                        current.width,
                        current.height,
                      ),
                    );
                    update(() {});
                  },
                ),
              ],
            ),
            cancelButton: SheetAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          );
        },
      ),
    );
  }

  void insertPage(int at) => edit(() => widget.note.document.insertPage(at));

  // Deletes the current page and offers its undo in a toast.
  void deletePage() => deletePageAt(page);

  void deletePageAt(int index) {
    final number = index + 1;
    edit(() {
      widget.note.document.deletePage(index);
      if (index < page) page--;
      page = page.clamp(0, widget.note.document.pageCount() - 1);
    });
    pageResultToast('Page $number deleted', true);
  }

  void deleteBlankPages() {
    final document = widget.note.document;
    final currentFile = document.navigation().toDart[page].file;
    final removed = document.deleteBlankPages();
    if (removed == 0) {
      pageResultToast('No blank pages', false);
      return;
    }
    final files = document.navigation().toDart;
    final samePage = files.take(document.pageCount()).toList().indexWhere(
      (mark) => mark.file == currentFile,
    );
    widget.note.saver.schedule();
    setState(() {
      page = samePage < 0
          ? page.clamp(0, document.pageCount() - 1)
          : samePage;
    });
    updateView();
    pageResultToast('$removed blank ${removed == 1 ? 'page' : 'pages'} deleted', true);
  }

  void pageResultToast(String message, bool undoable) {
    toastification.showCustom(
      alignment: Alignment.bottomCenter,
      autoCloseDuration: const Duration(seconds: 6),
      builder: (context, toast) => Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            color: surface2,
            borderRadius: BorderRadius.circular(12),
            boxShadow: floatingShadow,
          ),
          // The status and the Undo button are separate nodes. Without
          // container, the toast was one status node named "Page 4 deleted
          // Undo", with no Undo button.
          child: Semantics(
            explicitChildNodes: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  container: true,
                  role: SemanticsRole.status,
                  liveRegion: true,
                  child: Text(message, style: callout),
                ),
                if (undoable)
                  CupertinoButton(
                    onPressed: () {
                      toastification.dismiss(toast);
                      history(false);
                    },
                    child: Text('Undo', style: subhead),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
    final chosen = await showModalDialog<int>(
      context: context,
      builder: (context) => Alert(
        title: const Text('Go to page'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            cursorOpacityAnimates: false,
            decoration: fieldDecoration,
            placeholderStyle: placeholderText,
            controller: text,
            autofocus: true,
            placeholder: '1 to $count',
            keyboardType: TextInputType.number,
          ),
        ),
        actions: [
          AlertAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          AlertAction(
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

  // One share sheet chooses the PDF content and its destination.
  Future<void> shareNote() async {
    final layers = widget.note.document.layers().toDart;
    final included = {
      for (final layer in layers)
        if (!layer.hidden) layer.id,
    };
    final first = TextEditingController(text: '1');
    final last = TextEditingController(
      text: '${widget.note.document.pageCount()}',
    );
    final destination = await showModalDialog<String>(
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
              to <= widget.note.document.pageCount() &&
              included.isNotEmpty;
          return Alert(
            title: const Text('Share note'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text('Format', style: subhead),
                const SizedBox(height: 4),
                const Text('PDF'),
                const SizedBox(height: 16),
                Text('Page range', style: subhead),
                const SizedBox(height: 8),
                const Text('First page'),
                const SizedBox(height: 4),
                CupertinoTextField(
                  cursorOpacityAnimates: false,
                  decoration: fieldDecoration,
                  placeholderStyle: placeholderText,
                  controller: first,
                  placeholder: 'First page',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => update(() {}),
                ),
                const SizedBox(height: 12),
                const Text('Last page'),
                const SizedBox(height: 4),
                CupertinoTextField(
                  cursorOpacityAnimates: false,
                  decoration: fieldDecoration,
                  placeholderStyle: placeholderText,
                  controller: last,
                  placeholder: 'Last page',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => update(() {}),
                ),
                if (layers.length > 1) ...[
                  const SizedBox(height: 16),
                  Text('Included layers', style: subhead),
                ],
                if (layers.length > 1)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Each switch is named by its layer, as in Settings.
                          for (final layer in layers)
                            MergeSemantics(
                              child: CupertinoListTile(
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
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              AlertAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              AlertAction(
                onPressed: valid
                    ? () => Navigator.pop(context, 'download')
                    : null,
                child: const Text('Download PDF'),
              ),
              if (native.host.canSharePdf())
                AlertAction(
                  onPressed: valid
                      ? () => Navigator.pop(context, 'share')
                      : null,
                  child: const Text('Send to apps'),
                ),
            ],
          );
        },
      ),
    );
    if (destination != null) {
      await widget.note.saver.save().toDart;
      final from = int.parse(first.text) - 1;
      final count = int.parse(last.text) - from;
      final ids = included.map((id) => id.toJS).toList().toJS;
      first.dispose();
      last.dispose();
      switch (destination) {
        case 'share':
          await native.host.sharePdf(widget.note, from, count, ids).toDart;
        case 'download':
          native.host.exportPdf(widget.note, from, count, ids);
      }
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
    final action = await showModalSheet<String>(
      context: context,
      builder: (context) => ActionSheet(
        title: const Text('Link selected content'),
        actions: [
          SheetAction(
            onPressed: () => Navigator.pop(context, 'page'),
            child: const Text('Page or bookmark'),
          ),
          SheetAction(
            onPressed: () => Navigator.pop(context, 'note'),
            child: const Text('Another notebook'),
          ),
          SheetAction(
            onPressed: () => Navigator.pop(context, 'url'),
            child: const Text('URL or relative notebook path'),
          ),
        ],
        cancelButton: SheetAction(
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
      href = await showModalDialog<String>(
        context: context,
        builder: (context) => Alert(
          title: const Text('Link destination'),
          content: CupertinoTextField(
            cursorOpacityAnimates: false,
            decoration: fieldDecoration,
            placeholderStyle: placeholderText,
            controller: text,
            autofocus: true,
            placeholder: 'https://… or ../../Note/pages/0001.svg',
          ),
          actions: [
            AlertAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            AlertAction(
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
