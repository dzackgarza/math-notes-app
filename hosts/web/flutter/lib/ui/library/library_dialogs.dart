import 'dart:js_interop';

import 'package:flutter/cupertino.dart';

import '../../creation_sheet.dart';
import '../../host.dart' as native;
import '../../tag_editor.dart';
import 'library_view_model.dart';
import '../modal.dart';
import '../theme.dart';

Color hexColor(String value) =>
    Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);

const papers = {
  'dotted': 'Dot Paper',
  'grid-medium': 'Grid Paper',
  'lined-medium': 'Lined Paper',
  'blank': 'Plain Paper',
  'grid-fine': 'Graph Paper',
};

// The labels of every built-in template: those of `papers`, and the rulings
// that the creation sheets do not offer.
const paperLabels = {
  ...papers,
  'lined-wide': 'Lined Paper, wide',
  'lined-narrow': 'Lined Paper, narrow',
  'grid-coarse': 'Grid Paper, coarse',
};

CupertinoActionSheetAction cancelAction(BuildContext context) =>
    CupertinoActionSheetAction(
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancel'),
    );

// The name and color of a new tag; null when the user cancels.
Future<({String name, String color})?> askNewTag(BuildContext context) async {
  final name = TextEditingController();
  var color = native.host.tagColors.toDart.first.toDart;
  final accepted = await showModalDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => CupertinoAlertDialog(
        title: const Text('New tag'),
        content: Column(
          children: [
            CupertinoTextField(
              controller: name,
              placeholder: 'Tag name',
              autofocus: true,
              onChanged: (_) => update(() {}),
            ),
            Wrap(
              children: [
                for (final value in native.host.tagColors.toDart)
                  CupertinoButton(
                    onPressed: () => update(() => color = value.toDart),
                    child: Semantics(
                      label: value.toDart,
                      selected: color == value.toDart,
                      child: Icon(
                        CupertinoIcons.circle_fill,
                        color: hexColor(value.toDart),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Add tag'),
          ),
        ],
      ),
    ),
  );
  final title = name.text.trim();
  name.dispose();
  return accepted == true ? (name: title, color: color) : null;
}

// Edits the description and tags of a note in `metadata`; true when the user
// saves.
Future<bool> editNoteDetails(
  BuildContext context,
  String title,
  native.NoteMetadata metadata,
) async {
  final description = TextEditingController(text: metadata.description);
  final tags = TagEditingController(
    metadata.tags.toDart.map((s) => s.toDart).toList(),
  );
  final accepted = await showModalDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Column(
        children: [
          const SizedBox(height: 16),
          CupertinoTextField(
            controller: description,
            placeholder: 'Description',
            minLines: 2,
            maxLines: 5,
            maxLength: 500,
          ),
          const SizedBox(height: 12),
          TagEditor(controller: tags),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save details'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    metadata.description = description.text;
    metadata.tags = tags.tags.map((tag) => tag.toJS).toList().toJS;
  }
  description.dispose();
  tags.dispose();
  return accepted == true;
}

// Edits the description, tags and default paper of a notebook in `values`;
// true when the user saves.
Future<bool> editFolderDetails(
  BuildContext context,
  String title,
  native.FolderMetadata values,
) async {
  final description = TextEditingController(text: values.description);
  final tags = TagEditingController(
    values.tags.toDart.map((tag) => tag.toDart).toList(),
  );
  var paper = values.paper;
  final accepted = await showModalDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => CupertinoAlertDialog(
        title: Text('$title details'),
        content: Column(
          children: [
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: description,
              placeholder: 'Description',
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
            ),
            const SizedBox(height: 12),
            TagEditor(controller: tags),
            const SizedBox(height: 12),
            CupertinoSlidingSegmentedControl<String>(
              groupValue: paper,
              children: const {
                'dotted': Text('Dot'),
                'grid-medium': Text('Graph'),
                'blank': Text('Blank'),
                'lined-medium': Text('Ruled'),
              },
              onValueChanged: (value) {
                if (value != null) update(() => paper = value);
              },
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save details'),
          ),
        ],
      ),
    ),
  );
  if (accepted == true) {
    values.description = description.text;
    values.paper = paper;
    values.tags = tags.tags.map((tag) => tag.toJS).toList().toJS;
  }
  description.dispose();
  tags.dispose();
  return accepted == true;
}

Future<String?> askName(BuildContext context, String name) async {
  final controller = TextEditingController(text: name);
  final accepted = await showModalDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('Rename'),
      content: CupertinoTextField(
        controller: controller,
        placeholder: 'Name',
        autofocus: true,
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  final result = controller.text.trim();
  controller.dispose();
  return accepted == true ? result : null;
}

Future<native.Folder?> chooseFolder(
  BuildContext context,
  String title,
  List<native.Folder> folders,
  String Function(native.Folder) label,
) => showModalSheet<native.Folder>(
  context: context,
  builder: (context) => CupertinoActionSheet(
    title: Text(title),
    actions: [
      for (final item in folders)
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context, item),
          child: Text(label(item)),
        ),
    ],
    cancelButton: cancelAction(context),
  ),
);

String locationLabel(JSArray<JSString> path) =>
    native.pathKey(path).isEmpty ? 'My Notes' : native.pathKey(path);

// The creation form for a notebook (`isFolder`) or a note. The form starts
// from the saved draft, then from the defaults of the notebook it goes in.
Future<CreationForm?> askCreation(
  BuildContext context, {
  required bool isFolder,
  required native.Engine engine,
  required native.Directory root,
  required native.LibraryMetadata metadata,
  required List<native.Folder> folders,
  required JSArray<JSString>? notebook,
}) async {
  final defaults =
      metadata.folders[native.pathKey(notebook ?? <JSString>[].toJS)] ??
      native.host.emptyFolder();
  final draft = isFolder ? null : metadata.draft;
  final title = TextEditingController(text: draft?.title ?? '');
  final description = TextEditingController();
  final tags = TagEditingController(
    (draft?.tags ?? defaults.tags).toDart.map((tag) => tag.toDart).toList(),
  );
  final templateName = TextEditingController();
  var target = draft?.folder ?? notebook ?? <JSString>[].toJS;
  var paper = draft?.template ?? defaults.paper;
  var size = draft?.pageSize ?? 'a4';
  var orientation = draft?.orientation ?? 'portrait';
  var coverColor = defaults.coverColor;
  var coverStyle = defaults.coverStyle;
  var naming = false;
  final kind = isFolder ? 'notebook' : 'note';
  // The form as it opened; Escape, Cancel, or a tap outside asks before it
  // discards a change.
  String state() => [
    title.text,
    description.text,
    tags.tags.join('\n'),
    native.pathKey(target),
    paper,
    size,
    orientation,
    coverColor,
    coverStyle,
  ].join('\u0000');
  final opened = state();
  final action = await showModalDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => ListenableBuilder(
        listenable: Listenable.merge([title, description, tags, tags.input]),
        builder: (context, sheet) => PopScope<String>(
          canPop: state() == opened,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final discard = await showModalDialog<bool>(
              context: context,
              builder: (context) => CupertinoAlertDialog(
                title: Text('Discard new $kind?'),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep editing'),
                  ),
                  CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            );
            if (discard == true && context.mounted) Navigator.pop(context);
          },
          child: sheet!,
        ),
        child: CreationSheet(
          title: isFolder
              ? 'New notebook'
              : 'New note in ${folders.where((item) => native.pathKey(item.path) == native.pathKey(target)).firstOrNull?.name ?? locationLabel(target)}',
          preview: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Preview', style: headline),
              const SizedBox(height: 12),
              Expanded(
                child: PaperPreview(
                  engine: engine,
                  root: root,
                  paper: paper,
                  size: size,
                  orientation: orientation,
                ),
              ),
            ],
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(isFolder ? 'Notebook title' : 'Title', style: subhead),
              const SizedBox(height: 6),
              CupertinoTextField(
                controller: title,
                placeholder: isFolder ? 'Notebook title' : 'Title',
                autofocus: true,
                onChanged: (_) => update(() {}),
              ),
              if (isFolder) ...[
                const SizedBox(height: 12),
                Text('Description (optional)', style: subhead),
                const SizedBox(height: 6),
                CupertinoTextField(
                  controller: description,
                  placeholder: 'Description',
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                ),
                const SizedBox(height: 12),
                Text('Cover style', style: subhead),
                const SizedBox(height: 6),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: coverStyle,
                  children: const {
                    'classic': Text('Classic'),
                    'spine': Text('Spine'),
                  },
                  onValueChanged: (value) {
                    if (value != null) update(() => coverStyle = value);
                  },
                ),
                const SizedBox(height: 12),
                Text('Cover color', style: subhead),
                Row(
                  children: [
                    for (final color in const {
                      '#A9C1F5': 'Blue',
                      '#BFE8CC': 'Green',
                      '#E6C8F1': 'Purple',
                      '#F2D0BA': 'Peach',
                    }.entries)
                      Semantics(
                        label: color.value,
                        selected: coverColor == color.key,
                        button: true,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: () => update(() => coverColor = color.key),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: coverColor == color.key
                                    ? accentText
                                    : const Color(0x00000000),
                                width: 2,
                              ),
                            ),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hexColor(color.key),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Paper style', style: subhead),
              const SizedBox(height: 6),
              CupertinoSlidingSegmentedControl<String>(
                groupValue: paper,
                children: isFolder
                    ? const {
                        'dotted': Text('Dot'),
                        'grid-medium': Text('Graph'),
                        'blank': Text('Blank'),
                        'lined-medium': Text('Ruled'),
                      }
                    : {
                        for (final entry in papers.entries)
                          entry.key: Text(entry.value),
                      },
                onValueChanged: (value) {
                  if (value != null) update(() => paper = value);
                },
              ),
              const SizedBox(height: 12),
              Text('Tags', style: subhead),
              const SizedBox(height: 6),
              TagEditor(controller: tags),
              const SizedBox(height: 12),
              Text(isFolder ? 'Location' : 'Notebook', style: subhead),
              CupertinoButton(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final selected = await chooseFolder(
                    context,
                    isFolder ? 'Choose location' : 'Choose notebook',
                    folders,
                    (item) => locationLabel(item.path),
                  );
                  if (selected != null) update(() => target = selected.path);
                },
                child: Text(
                  isFolder
                      ? locationLabel(target)
                      : 'Change notebook · ${folders.where((item) => native.pathKey(item.path) == native.pathKey(target)).firstOrNull?.name ?? locationLabel(target)}',
                ),
              ),
              if (isFolder)
                Text(
                  'You can move this notebook later.',
                  style: footnote.copyWith(color: secondaryLabel),
                ),
              if (!isFolder) ...[
                const SizedBox(height: 12),
                Text('Page size', style: subhead),
                const SizedBox(height: 6),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: size,
                  children: const {'a4': Text('A4'), 'letter': Text('Letter')},
                  onValueChanged: (value) {
                    if (value != null) update(() => size = value);
                  },
                ),
                const SizedBox(height: 12),
                Text('Orientation', style: subhead),
                const SizedBox(height: 6),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: orientation,
                  children: const {
                    'portrait': Text('Portrait'),
                    'landscape': Text('Landscape'),
                  },
                  onValueChanged: (value) {
                    if (value != null) update(() => orientation = value);
                  },
                ),
                const SizedBox(height: 16),
                Text('Starting template', style: subhead),
                for (final settings in metadata.startingTemplates.toDart)
                  CupertinoButton(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    onPressed: () => update(() {
                      target = settings.folder;
                      paper = settings.paper;
                      size = settings.pageSize;
                      orientation = settings.orientation ?? 'portrait';
                      tags.replace(
                        settings.tags.toDart.map((tag) => tag.toDart).toList(),
                      );
                    }),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(settings.name),
                        Text(
                          '${papers[settings.paper] ?? settings.paper} · ${settings.pageSize.toUpperCase()} · ${settings.tags.length} tag${settings.tags.length == 1 ? '' : 's'}',
                          style: footnote.copyWith(color: secondaryLabel),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                if (!naming)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CupertinoButton.tinted(
                      sizeStyle: CupertinoButtonSize.medium,
                      onPressed: () => update(() => naming = true),
                      child: const Text('Save as template'),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: templateName,
                          placeholder: 'Template name',
                          autofocus: true,
                          onChanged: (_) => update(() {}),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: templateName.text.trim().isEmpty
                            ? null
                            : () => Navigator.pop(context, 'template'),
                        child: const Text('Save template'),
                      ),
                    ],
                  ),
              ],
            ],
          ),
          actions: [
            CupertinoButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Cancel'),
            ),
            if (!isFolder)
              CupertinoButton(
                onPressed: () => Navigator.pop(context, 'draft'),
                child: const Text('Save as draft'),
              ),
            CupertinoButton.filled(
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, 'create'),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    ),
  );
  final form = (
    action: action ?? '',
    name: title.text.trim(),
    tags: tags.tags.map((tag) => tag.toJS).toList().toJS,
    description: description.text,
    settingsName: templateName.text.trim(),
    target: target,
    paper: paper,
    size: size,
    orientation: orientation,
    coverColor: coverColor,
    coverStyle: coverStyle,
  );
  title.dispose();
  description.dispose();
  tags.dispose();
  templateName.dispose();
  return action == null ? null : form;
}
