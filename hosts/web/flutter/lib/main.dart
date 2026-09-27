import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';

import 'host.dart' as native;
import 'notebook.dart';
import 'creation_sheet.dart';
import 'note_thumbnail.dart';

void main() {
  runApp(const MathNotes());
  SemanticsBinding.instance.ensureSemantics();
}

class MathNotes extends StatelessWidget {
  const MathNotes({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoApp(
    title: 'Math Notes',
    theme: CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: Color(0xFF2F6FEB),
    ),
    home: Workspace(),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  native.Engine? engine;
  native.Directory? root;
  native.Library? library;
  final opened = <native.OpenNote>[];
  int tab = 0;
  bool inLibrary = true;
  native.OpenNote? get active =>
      inLibrary || opened.isEmpty ? null : opened[tab];
  set active(native.OpenNote? note) {
    if (note == null) {
      inLibrary = true;
      return;
    }
    final index = opened.indexWhere(
      (item) => native.pathKey(item.path) == native.pathKey(note.path),
    );
    if (index < 0) {
      opened.add(note);
      tab = opened.length - 1;
    } else {
      tab = index;
    }
    inLibrary = false;
  }

  final search = TextEditingController();
  JSArray<JSString> folder = <JSString>[].toJS;
  bool reconnect = false;
  bool busy = true;
  String? failure;
  String? confirmation;
  String section = 'folder';
  String sort = 'name';
  String? selectedTag;
  bool grid = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      run(() async {
        engine = await native.host.loadEngine().toDart;
        await native.host.cacheApp().toDart;
        final start = await native.host.startRoot().toDart;
        root = start.root;
        reconnect = start.needsGesture;
        if (root != null && !reconnect) await refresh();
      }),
    );
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => failure = error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    library = await native.host.library(root!, engine!).toDart;
  }

  Future<void> chooseRoot() async {
    final chosen = await native.host.pickRoot().toDart;
    for (final note in opened) {
      await note.saver.save().toDart;
    }
    setState(() {
      opened.clear();
      tab = 0;
      root = chosen;
      folder = <JSString>[].toJS;
      section = 'folder';
      reconnect = false;
      inLibrary = true;
    });
    await refresh();
  }

  native.NoteMetadata noteMetadata(native.Note note) =>
      library!.metadata.notes[native.pathKey(note.path)] ??
      native.host.emptyNote();

  void registerTags(native.LibraryMetadata metadata, JSArray<JSString> names) {
    final tags = metadata.tags.toDart.toList();
    final colors = native.host.tagColors.toDart;
    for (final name in names.toDart) {
      if (!tags.any((tag) => tag.name == name.toDart)) {
        tags.add(
          native.Tag.create(
            name: name.toDart,
            color: colors[tags.length % colors.length].toDart,
          ),
        );
      }
    }
    metadata.tags = tags.toJS;
  }

  Future<void> addTag() async {
    final name = TextEditingController();
    var color = native.host.tagColors.toDart.first.toDart;
    final accepted = await showCupertinoDialog<bool>(
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
                          color: Color(
                            int.parse(value.toDart.substring(1), radix: 16) |
                                0xFF000000,
                          ),
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
    if (accepted != true) return;
    final metadata = await native.host.readMetadata(root!).toDart;
    if (metadata.tags.toDart.any((tag) => tag.name == title))
      throw StateError('This tag name is already in use.');
    metadata.tags = [
      ...metadata.tags.toDart,
      native.Tag.create(name: title, color: color),
    ].toJS;
    await native.host.writeMetadata(root!, metadata).toDart;
    await refresh();
  }

  Future<void> saveNoteMetadata(
    native.Note note,
    native.NoteMetadata metadata,
  ) async {
    final current = await native.host.readMetadata(root!).toDart;
    current.notes[native.pathKey(note.path)] = metadata;
    registerTags(current, metadata.tags);
    await native.host.writeMetadata(root!, current).toDart;
    await refresh();
  }

  Future<void> details(native.Note note) async {
    final metadata = noteMetadata(note);
    final description = TextEditingController(text: metadata.description);
    final tags = TextEditingController(
      text: metadata.tags.toDart.map((s) => s.toDart).join(', '),
    );
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(note.name),
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
            Semantics(
              label: 'Tags, separated by commas',
              child: CupertinoTextField(
                controller: tags,
                prefix: const ExcludeSemantics(
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Text('Tags'),
                  ),
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
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save details'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      metadata.description = description.text;
      metadata.tags = tags.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .map((tag) => tag.toJS)
          .toList()
          .toJS;
      await saveNoteMetadata(note, metadata);
    }
    description.dispose();
    tags.dispose();
  }

  Future<void> relocate(native.Note note, String action) async {
    var name = note.name;
    var parent = note.path.toDart.sublist(0, note.path.length - 1).toJS;
    if (action == 'rename') {
      final controller = TextEditingController(text: name);
      final accepted = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Rename note'),
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
      name = controller.text.trim();
      controller.dispose();
      if (accepted != true) return;
    }
    if (action == 'move' || action == 'restore') {
      final target = await showCupertinoModalPopup<native.Folder>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('Choose notebook'),
          actions: [
            for (final item in library!.folders.toDart)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, item),
                child: Text(item.name),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
      );
      if (target == null) return;
      parent = target.path;
    }
    final index = opened.indexWhere(
      (item) => native.pathKey(item.path) == native.pathKey(note.path),
    );
    if (index >= 0) {
      await opened[index].saver.save().toDart;
      setState(() {
        opened.removeAt(index);
        tab = opened.isEmpty ? 0 : tab.clamp(0, opened.length - 1);
      });
    }
    final to = action == 'trash'
        ? await native.host.moveToTrash(root!, note.path).toDart
        : await native.host.moveEntry(root!, note.path, parent, name).toDart;
    final metadata = await native.host.readMetadata(root!).toDart;
    await native.host
        .writeMetadata(root!, native.host.moveNotes(metadata, note.path, to))
        .toDart;
    await refresh();
  }

  Future<void> noteActions(native.Note note) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(note.name),
        actions: [
          if (section == 'trash')
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'restore'),
              child: const Text('Restore'),
            )
          else ...[
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'favorite'),
              child: Text(
                noteMetadata(note).favorite
                    ? 'Remove favorite'
                    : 'Add favorite',
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'details'),
              child: const Text('Details and tags'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'rename'),
              child: const Text('Rename'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'move'),
              child: const Text('Move'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'trash'),
              child: const Text('Move to trash'),
            ),
          ],
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (action == null) return;
    if (action == 'favorite') {
      final metadata = noteMetadata(note);
      metadata.favorite = !metadata.favorite;
      await saveNoteMetadata(note, metadata);
    } else if (action == 'details') {
      await details(note);
    } else {
      await relocate(note, action);
    }
  }

  Future<void> open(JSArray<JSString> path) async {
    if (active != null) await active!.saver.save().toDart;
    final index = opened.indexWhere(
      (item) => native.pathKey(item.path) == native.pathKey(path),
    );
    if (index >= 0) {
      setState(() {
        tab = index;
        inLibrary = false;
      });
      return;
    }
    final note = await native.host.openNotebook(engine!, root!, path).toDart;
    setState(() => active = note);
  }

  Future<void> create(bool isFolder) async {
    setState(() => confirmation = null);
    final metadata = library!.metadata;
    final defaults =
        metadata.folders[native.pathKey(folder)] ?? native.host.emptyFolder();
    final draft = isFolder ? null : metadata.draft;
    final title = TextEditingController(text: draft?.title ?? '');
    final description = TextEditingController();
    final tags = TextEditingController(
      text: (draft?.tags ?? defaults.tags).toDart
          .map((tag) => tag.toDart)
          .join(', '),
    );
    final templateName = TextEditingController();
    var target = draft?.folder ?? folder;
    var paper = draft?.template ?? defaults.paper;
    var size = draft?.pageSize ?? 'a4';
    var coverColor = defaults.coverColor;
    var coverStyle = defaults.coverStyle;
    final accepted = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CreationSheet(
          title: Text(isFolder ? 'New Notebook' : 'New Note'),
          preview: PaperPreview(
            engine: engine!,
            root: root!,
            paper: paper,
            size: size,
          ),
          content: Column(
            children: [
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: title,
                placeholder: 'Title',
                autofocus: true,
                onChanged: (_) => update(() {}),
              ),
              if (isFolder) ...[
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: description,
                  placeholder: 'Description',
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                ),
                const SizedBox(height: 12),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: coverStyle,
                  children: const {
                    'classic': Text('Classic cover'),
                    'spine': Text('Spine cover'),
                  },
                  onValueChanged: (value) {
                    if (value != null) update(() => coverStyle = value);
                  },
                ),
                Wrap(
                  children: [
                    for (final color in const {
                      '#A9C1F5': 'Blue',
                      '#BFE8CC': 'Green',
                      '#E6C8F1': 'Purple',
                      '#F2D0BA': 'Peach',
                    }.entries)
                      CupertinoButton(
                        onPressed: () => update(() => coverColor = color.key),
                        child: Text(
                          color.value,
                          style: TextStyle(
                            fontWeight: coverColor == color.key
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              ...[
                const SizedBox(height: 16),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: paper,
                  children: const {
                    'blank': Text('Plain'),
                    'dotted': Text('Dot'),
                    'grid-medium': Text('Grid'),
                    'lined-medium': Text('Ruled'),
                  },
                  onValueChanged: (value) {
                    if (value != null) update(() => paper = value);
                  },
                ),
              ],
              const SizedBox(height: 12),
              Semantics(
                label: 'Tags, separated by commas',
                child: CupertinoTextField(
                  controller: tags,
                  prefix: const ExcludeSemantics(
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Text('Tags'),
                    ),
                  ),
                ),
              ),
              if (!isFolder) ...[
                const SizedBox(height: 12),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: size,
                  children: const {'a4': Text('A4'), 'letter': Text('Letter')},
                  onValueChanged: (value) {
                    if (value != null) update(() => size = value);
                  },
                ),
                CupertinoButton(
                  onPressed: () async {
                    final selected =
                        await showCupertinoModalPopup<native.Folder>(
                          context: context,
                          builder: (context) => CupertinoActionSheet(
                            title: const Text('Choose notebook'),
                            actions: [
                              for (final item in library!.folders.toDart)
                                CupertinoActionSheetAction(
                                  onPressed: () => Navigator.pop(context, item),
                                  child: Text(item.name),
                                ),
                            ],
                            cancelButton: CupertinoActionSheetAction(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                        );
                    if (selected != null) update(() => target = selected.path);
                  },
                  child: Text(
                    'Notebook: ${native.pathKey(target).isEmpty ? 'My Notes' : native.pathKey(target)}',
                  ),
                ),
                for (final settings in metadata.startingTemplates.toDart)
                  CupertinoButton(
                    onPressed: () => update(() {
                      target = settings.folder;
                      paper = settings.paper;
                      size = settings.pageSize;
                      tags.text = settings.tags.toDart
                          .map((tag) => tag.toDart)
                          .join(', ');
                    }),
                    child: Text(settings.name),
                  ),
                CupertinoTextField(
                  controller: templateName,
                  placeholder: 'Settings name',
                  onChanged: (_) => update(() {}),
                ),
                CupertinoButton(
                  onPressed: templateName.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context, 'template'),
                  child: const Text('Save as template'),
                ),
              ],
            ],
          ),
          actions: [
            CupertinoButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (!isFolder)
              CupertinoButton(
                onPressed: () => Navigator.pop(context, 'draft'),
                child: const Text('Save as Draft'),
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
    );
    final name = title.text.trim();
    final chosenTags = tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .map((tag) => tag.toJS)
        .toList()
        .toJS;
    final descriptionText = description.text;
    final settingsName = templateName.text.trim();
    title.dispose();
    description.dispose();
    tags.dispose();
    templateName.dispose();
    if (accepted == null) return;
    await run(() async {
      final current = await native.host.readMetadata(root!).toDart;
      registerTags(current, chosenTags);
      if (accepted == 'draft') {
        current.draft = native.NoteDraft.create(
          folder: target,
          title: name,
          template: paper,
          tags: chosenTags,
          pageSize: size,
        );
        await native.host.writeMetadata(root!, current).toDart;
        await refresh();
        setState(() => confirmation = 'Draft saved');
        return;
      }
      if (accepted == 'template') {
        current.startingTemplates = [
          ...current.startingTemplates.toDart.where(
            (item) => item.name != settingsName,
          ),
          native.StartingTemplate.create(
            name: settingsName,
            folder: target,
            paper: paper,
            pageSize: size,
            tags: chosenTags,
          ),
        ].toJS;
        await native.host.writeMetadata(root!, current).toDart;
        await refresh();
        setState(() => confirmation = 'Template saved');
        return;
      }
      if (isFolder) {
        folder = await native.host.createFolder(root!, folder, name).toDart;
        final values = native.host.emptyFolder();
        values.description = descriptionText;
        values.paper = paper;
        values.coverColor = coverColor;
        values.coverStyle = coverStyle;
        values.tags = chosenTags;
        current.folders[native.pathKey(folder)] = values;
      } else {
        active = await native.host
            .createNotebook(engine!, root!, target, name, paper, size)
            .toDart;
        final values = native.host.emptyNote();
        values.tags = chosenTags;
        current.notes[native.pathKey(active!.path)] = values;
        current.clearDraft();
      }
      await native.host.writeMetadata(root!, current).toDart;
      await refresh();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: active == null ? 0 : 1,
      children: [
        ExcludeFocus(excluding: !inLibrary, child: buildLibrary(context)),
        Column(
          children: [
            SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Expanded(
                    child: opened.length > 1
                        ? CupertinoSlidingSegmentedControl<int>(
                            groupValue: tab,
                            children: {
                              for (var i = 0; i < opened.length; i++)
                                i: Text(opened[i].name),
                            },
                            onValueChanged: (index) {
                              if (index != null)
                                unawaited(run(() => open(opened[index].path)));
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              opened.isEmpty ? '' : opened.first.name,
                            ),
                          ),
                  ),
                  CupertinoButton(
                    onPressed: () => run(pickNote),
                    child: Semantics(
                      label: 'Open note',
                      child: const Icon(CupertinoIcons.add),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: opened.isEmpty
                        ? null
                        : () => run(() async {
                            await opened[tab].saver.save().toDart;
                            setState(() {
                              opened.removeAt(tab);
                              tab = tab.clamp(
                                0,
                                opened.length - 1 < 0 ? 0 : opened.length - 1,
                              );
                              if (opened.isEmpty) inLibrary = true;
                            });
                            await refresh();
                          }),
                    child: Semantics(
                      label: 'Close note',
                      child: const Icon(CupertinoIcons.xmark),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: opened.isEmpty ? null : tab,
                children: [
                  for (var i = 0; i < opened.length; i++)
                    TickerMode(
                      key: ValueKey(native.pathKey(opened[i].path)),
                      enabled: !inLibrary && i == tab,
                      child: ExcludeFocus(
                        excluding: inLibrary || i != tab,
                        child: Notebook(
                          note: opened[i],
                          engine: engine!,
                          onLibrary: () => run(() async {
                            for (final note in opened) {
                              await note.saver.save().toDart;
                            }
                            await refresh();
                            setState(() => inLibrary = true);
                          }),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pickNote() async {
    await refresh();
    if (!mounted) return;
    final filter = TextEditingController();
    final picked = await showCupertinoModalPopup<native.Note>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CupertinoPopupSurface(
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.7,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Open note'),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: CupertinoSearchTextField(
                      controller: filter,
                      onChanged: (_) => update(() {}),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final folder in library!.folders.toDart)
                          for (final note in folder.notes.toDart.where(
                            (item) => item.name.toLowerCase().contains(
                              filter.text.toLowerCase(),
                            ),
                          ))
                            CupertinoListTile(
                              title: Text(note.name),
                              leadingSize: 48,
                              leading: NoteThumbnail(
                                engine: engine!,
                                root: root!,
                                note: note,
                              ),
                              subtitle: Text(folder.name),
                              onTap: () => Navigator.pop(context, note),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    filter.dispose();
    if (picked != null) await open(picked.path);
  }

  Widget buildLibrary(BuildContext context) {
    final connected = root != null && !reconnect && library != null;
    final selected = library?.folders.toDart
        .where((item) => native.pathKey(item.path) == native.pathKey(folder))
        .firstOrNull;
    final all =
        library?.folders.toDart.expand((item) => item.notes.toDart).toList() ??
        <native.Note>[];
    final candidates = section == 'trash'
        ? library!.trash.toDart
        : section == 'folder' && search.text.isEmpty
        ? selected?.notes.toDart ?? <native.Note>[]
        : all;
    final notes = candidates.where((note) {
      final metadata = noteMetadata(note);
      if (section == 'favorites' && !metadata.favorite) return false;
      if (section == 'tag' &&
          !metadata.tags.toDart.any((tag) => tag.toDart == selectedTag))
        return false;
      final text =
          '${note.name} ${metadata.description} ${metadata.tags.toDart.map((tag) => tag.toDart).join(' ')}'
              .toLowerCase();
      return text.contains(search.text.toLowerCase());
    }).toList();
    notes.sort(
      (a, b) => section == 'recent' || sort == 'modified'
          ? b.modified.compareTo(a.modified)
          : a.name.compareTo(b.name),
    );
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Math Notes'),
        trailing: busy ? const CupertinoActivityIndicator() : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (confirmation != null)
              Semantics(
                role: SemanticsRole.status,
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(confirmation!),
                ),
              ),
            if (failure != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    failure!,
                    style: const TextStyle(
                      color: CupertinoColors.destructiveRed,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: connected
                  ? Row(
                      children: [
                        SizedBox(
                          width: 240,
                          child: ListView(
                            children: [
                              CupertinoListSection(
                                header: const Text('NOTEBOOKS'),
                                children: [
                                  for (final item in const {
                                    'library': 'Library',
                                    'search': 'Search',
                                    'recent': 'Recent',
                                    'favorites': 'Favorites',
                                    'trash': 'Trash',
                                  }.entries)
                                    CupertinoListTile(
                                      title: Text(item.value),
                                      backgroundColor: section == item.key
                                          ? const Color(0xFFE3EBFC)
                                          : null,
                                      onTap: () =>
                                          setState(() => section = item.key),
                                    ),
                                  for (final item in library!.folders.toDart)
                                    CupertinoListTile(
                                      title: Text(item.name),
                                      leading: const Icon(
                                        CupertinoIcons.folder,
                                      ),
                                      backgroundColor:
                                          section == 'folder' &&
                                              native.pathKey(item.path) ==
                                                  native.pathKey(folder)
                                          ? const Color(0xFFE3EBFC)
                                          : null,
                                      onTap: () => setState(() {
                                        folder = item.path;
                                        section = 'folder';
                                      }),
                                    ),
                                  CupertinoListTile(
                                    title: const Text('Choose notes folder'),
                                    leading: const Icon(
                                      CupertinoIcons.folder_open,
                                    ),
                                    onTap: () => run(chooseRoot),
                                  ),
                                ],
                              ),
                              CupertinoListSection(
                                header: const Text('TAGS'),
                                children: [
                                  for (final tag
                                      in library!.metadata.tags.toDart)
                                    CupertinoListTile(
                                      title: Text(tag.name),
                                      backgroundColor:
                                          section == 'tag' &&
                                              selectedTag == tag.name
                                          ? const Color(0xFFE3EBFC)
                                          : null,
                                      leading: Icon(
                                        CupertinoIcons.circle_fill,
                                        color: Color(
                                          int.parse(
                                                tag.color.substring(1),
                                                radix: 16,
                                              ) |
                                              0xFF000000,
                                        ),
                                      ),
                                      trailing: Text(
                                        '${all.where((note) => noteMetadata(note).tags.toDart.any((name) => name.toDart == tag.name)).length}',
                                      ),
                                      onTap: () => setState(() {
                                        selectedTag = tag.name;
                                        section = 'tag';
                                      }),
                                    ),
                                  CupertinoListTile(
                                    title: const Text('Add tag'),
                                    leading: const Icon(CupertinoIcons.add),
                                    onTap: () => run(addTag),
                                  ),
                                ],
                              ),
                              CupertinoListTile(
                                title: const Text('Settings'),
                                leading: const Icon(CupertinoIcons.settings),
                                onTap: () => showCupertinoModalPopup<void>(
                                  context: context,
                                  builder: (context) => CupertinoActionSheet(
                                    title: const Text('Settings'),
                                    actions: [
                                      CupertinoActionSheetAction(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          unawaited(run(chooseRoot));
                                        },
                                        child: const Text(
                                          'Choose notes folder',
                                        ),
                                      ),
                                      CupertinoActionSheetAction(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          unawaited(run(refresh));
                                        },
                                        child: const Text('Refresh library'),
                                      ),
                                    ],
                                    cancelButton: CupertinoActionSheetAction(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        switch (section) {
                                          'recent' => 'Recent',
                                          'favorites' => 'Favorites',
                                          'trash' => 'Trash',
                                          'tag' => selectedTag!,
                                          'library' => 'Library',
                                          'search' => 'Search',
                                          _ => selected?.name ?? 'Library',
                                        },
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    CupertinoButton(
                                      onPressed: busy
                                          ? null
                                          : () => create(true),
                                      child: const Text('New Notebook'),
                                    ),
                                    CupertinoButton.filled(
                                      onPressed: busy
                                          ? null
                                          : () => create(false),
                                      child: const Text('New Note'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                CupertinoSearchTextField(
                                  controller: search,
                                  placeholder: 'Search notes',
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child:
                                          CupertinoSlidingSegmentedControl<
                                            String
                                          >(
                                            groupValue: sort,
                                            children: const {
                                              'name': Text('Name'),
                                              'modified': Text('Last modified'),
                                            },
                                            onValueChanged: (value) {
                                              if (value != null)
                                                setState(() => sort = value);
                                            },
                                          ),
                                    ),
                                    const SizedBox(width: 16),
                                    CupertinoSlidingSegmentedControl<bool>(
                                      groupValue: grid,
                                      children: const {
                                        false: Text('List'),
                                        true: Text('Grid'),
                                      },
                                      onValueChanged: (value) {
                                        if (value != null)
                                          setState(() => grid = value);
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: grid
                                      ? GridView.extent(
                                          maxCrossAxisExtent: 260,
                                          mainAxisSpacing: 16,
                                          crossAxisSpacing: 16,
                                          childAspectRatio: 0.72,
                                          children: [
                                            for (final item in notes)
                                              DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: CupertinoColors.white,
                                                  border: Border.all(
                                                    color: CupertinoColors
                                                        .separator,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Column(
                                                  children: [
                                                    Expanded(
                                                      child: CupertinoButton(
                                                        onPressed: () => run(
                                                          () =>
                                                              section == 'trash'
                                                              ? noteActions(
                                                                  item,
                                                                )
                                                              : open(item.path),
                                                        ),
                                                        child: NoteThumbnail(
                                                          engine: engine!,
                                                          root: root!,
                                                          note: item,
                                                        ),
                                                      ),
                                                    ),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 12,
                                                                ),
                                                            child: Text(
                                                              item.name,
                                                            ),
                                                          ),
                                                        ),
                                                        CupertinoButton(
                                                          onPressed: () => run(
                                                            () => noteActions(
                                                              item,
                                                            ),
                                                          ),
                                                          child: Semantics(
                                                            label:
                                                                '${item.name} actions',
                                                            child: const Icon(
                                                              CupertinoIcons
                                                                  .ellipsis,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            12,
                                                          ),
                                                      child: Text(
                                                        noteMetadata(item)
                                                            .description,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        )
                                      : ListView(
                                          children: [
                                            for (final item in notes)
                                              CupertinoListTile.notched(
                                                leadingSize: 48,
                                                title: CupertinoButton(
                                                  padding: EdgeInsets.zero,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  onPressed: section == 'trash'
                                                      ? () => run(
                                                          () =>
                                                              noteActions(item),
                                                        )
                                                      : () => run(
                                                          () => open(item.path),
                                                        ),
                                                  child: Text(item.name),
                                                ),
                                                subtitle: Text(
                                                  noteMetadata(item).tags.toDart
                                                      .map((tag) => tag.toDart)
                                                      .join(' · '),
                                                ),
                                                leading: NoteThumbnail(
                                                  engine: engine!,
                                                  root: root!,
                                                  note: item,
                                                ),
                                                trailing: CupertinoButton(
                                                  padding: EdgeInsets.zero,
                                                  onPressed: () => run(
                                                    () => noteActions(item),
                                                  ),
                                                  child: Semantics(
                                                    label:
                                                        '${item.name} actions',
                                                    child: const Icon(
                                                      CupertinoIcons.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.book, size: 64),
                          const SizedBox(height: 24),
                          const Text(
                            'Your notes live in a folder on this device.',
                          ),
                          const SizedBox(height: 24),
                          if (reconnect)
                            CupertinoButton.filled(
                              onPressed: () => run(() async {
                                final granted = await native.host
                                    .requestPermission(root!)
                                    .toDart;
                                if (!granted.toDart)
                                  throw StateError(
                                    'Folder permission was denied. Reconnect to open your notes.',
                                  );
                                reconnect = false;
                                await refresh();
                              }),
                              child: const Text('Reconnect folder'),
                            ),
                          CupertinoButton(
                            onPressed: engine == null
                                ? null
                                : () => run(chooseRoot),
                            child: const Text('Choose notes folder'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
