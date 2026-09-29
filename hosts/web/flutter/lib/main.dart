import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show PlatformDispatcher;

import 'package:web/web.dart' as web;

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:toastification/toastification.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:path/path.dart' as paths;

import 'errors.dart';
import 'host.dart' as native;
import 'notebook.dart';
import 'creation_sheet.dart';
import 'note_thumbnail.dart';
import 'conflict_sheet.dart';
import 'bookmarks_sheet.dart';
import 'tag_editor.dart';

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    showError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    showError(error, stack);
    return true;
  };
  web.window.addEventListener(
    'unhandledrejection',
    ((web.PromiseRejectionEvent event) => showError(
      event.reason.dartify() ?? 'A promise failed.',
    )).toJS,
  );
  web.window.addEventListener(
    'error',
    ((web.ErrorEvent event) => showError(event.message)).toJS,
  );
  runApp(const MathNotes());
  SemanticsBinding.instance.ensureSemantics();
}

class MathNotes extends StatelessWidget {
  const MathNotes({super.key});
  @override
  Widget build(BuildContext context) => const ToastificationWrapper(
    child: CupertinoApp(
      title: 'Math Notes',
      theme: CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: accent,
        scaffoldBackgroundColor: chrome,
        barBackgroundColor: chromeBar,
      ),
      home: Workspace(),
    ),
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
  final captures = <String>{};
  final panes = MultiSplitViewController(areas: [Area(id: 'main')]);
  String? secondary;
  bool rightFocused = false;
  Axis splitAxis = Axis.horizontal;
  bool linkedViews = false;
  // The tab bar is shown at the top or hidden; the choice belongs to the
  // device.
  bool tabsHidden = web.window.localStorage.getItem('tabBar') == 'hidden';
  final viewport = ValueNotifier<NotebookViewport?>(null);
  final destination = ValueNotifier<NoteDestination?>(null);

  native.OpenNote? get secondaryNote {
    for (final note in opened) {
      if (native.pathKey(note.path) == secondary) return note;
    }
    return null;
  }

  void releaseNotes(List<native.OpenNote> notes) {
    if (notes.any((note) => native.pathKey(note.path) == secondary))
      closeSplit();
    // Canvases are disposed in the next frame before their shared document.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final note in notes) note.document.free();
    });
  }

  void closeSplit() {
    secondary = null;
    rightFocused = false;
    if (panes.areasCount > 1) panes.removeAreaAt(1);
  }

  Future<void> splitNote() async {
    if (captures.isNotEmpty)
      throw StateError('Complete the drawing before splitting notes.');
    setState(() {
      if (secondary != null) {
        closeSplit();
      } else {
        secondary = native.pathKey(opened[tab].path);
        panes.addArea(Area(id: 'reference'));
      }
    });
  }

  Future<void> chooseReference() async {
    final previous = tab;
    await pickNote();
    setState(() {
      secondary = native.pathKey(opened[tab].path);
      tab = previous;
      rightFocused = true;
    });
  }

  Future<void> showLibrary() => run(() async {
    if (captures.isNotEmpty)
      throw StateError('Complete the drawing before returning to the library.');
    setState(() => inLibrary = true);
    await saveOpened();
    await refresh();
  });
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
  // The open notebook; null shows the Notebooks view.
  JSArray<JSString>? folder;
  bool reconnect = false;
  bool busy = true;
  String? confirmation;
  String filter = 'all';
  String sort = 'name';
  bool ascending = true;
  String? selectedTag;
  bool grid = true;

  @override
  void initState() {
    super.initState();
    // The offline cache fills in the background; the app does not wait for it.
    unawaited(
      deadline(
        'Saving the app for offline use',
        const Duration(minutes: 2),
        native.host.cacheApp().toDart,
      ).then((_) {}, onError: showError),
    );
    unawaited(
      run(() async {
        engine = await deadline(
          'Loading the engine',
          const Duration(seconds: 30),
          native.host.loadEngine().toDart,
        );
        if (mounted) setState(() {});
        final start = await deadline(
          'Opening the saved notes folder',
          const Duration(seconds: 30),
          native.host.startRoot().toDart,
        );
        root = start.root;
        reconnect = start.needsGesture;
        if (root == null || reconnect) return;
        await watch();
        await refresh();
      }),
    );
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (error, stack) {
      showError(error, stack);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Saves every open note. The list is read before the first await, so a
  // note that opens while the saves run cannot invalidate the iteration.
  Future<void> saveOpened() async {
    await Future.wait([for (final note in opened) note.saver.save().toDart]);
  }

  // Reads overlap when the user acts during a read. Only the newest read
  // replaces the library, so an older read cannot show stale notes.
  int reads = 0;
  Future<void> refresh() async {
    final read = ++reads;
    final result = await deadline(
      'Reading the notes folder',
      const Duration(seconds: 60),
      native.host.library(root!, engine!).toDart,
    );
    if (read == reads && mounted) setState(() => library = result);
  }

  // The library follows the notes folder. A change from this app or from
  // another program (for example a sync client) reads the folder again.
  // An open note does not need the library; showLibrary reads it on return.
  native.RootObserver? observer;
  Timer? changes;
  Future<void> watch() async {
    observer?.disconnect();
    observer = await native.host
        .watchRoot(
          root!,
          (() {
            changes?.cancel();
            changes = Timer(const Duration(milliseconds: 500), () {
              if (inLibrary) refresh().then((_) {}, onError: showError);
            });
          }).toJS,
        )
        .toDart;
  }

  // A step that neither finishes nor throws is a failure: it fails with a
  // message that names the step.
  Future<T> deadline<T>(String step, Duration limit, Future<T> future) =>
      future.timeout(
        limit,
        onTimeout: () => throw TimeoutException(
          '$step did not finish in ${limit.inSeconds} s.',
        ),
      );

  Future<void> chooseRoot() async {
    final chosen = await native.host.pickRoot().toDart;
    await saveOpened();
    setState(() {
      releaseNotes(opened.toList());
      opened.clear();
      tab = 0;
      root = chosen;
      folder = null;
      reconnect = false;
      inLibrary = true;
    });
    await watch();
    await refresh();
  }

  native.NoteMetadata noteMetadata(native.Note note) =>
      library!.metadata.notes[native.pathKey(note.path)] ??
      native.host.emptyNote();

  String noteTitle(native.Note note) =>
      note.conflicts > 0 ? '⚠ ${note.name}' : note.name;

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
    final tags = TagEditingController(
      metadata.tags.toDart.map((s) => s.toDart).toList(),
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
      await saveNoteMetadata(note, metadata);
    }
    description.dispose();
    tags.dispose();
  }

  Future<void> relocate(JSArray<JSString> path, String action) async {
    var name = path.toDart.last.toDart;
    var parent = path.toDart.sublist(0, path.length - 1).toJS;
    if (action == 'rename') {
      final controller = TextEditingController(text: name);
      final accepted = await showCupertinoDialog<bool>(
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
    final prefix = native.pathKey(path);
    final affected = opened
        .where(
          (item) =>
              native.pathKey(item.path) == prefix ||
              native.pathKey(item.path).startsWith('$prefix/'),
        )
        .toList();
    for (final item in affected) {
      await item.saver.save().toDart;
    }
    setState(() {
      releaseNotes(affected);
      opened.removeWhere((item) => affected.contains(item));
      tab = opened.isEmpty ? 0 : tab.clamp(0, opened.length - 1);
    });
    final to = action == 'trash'
        ? await native.host.moveToTrash(root!, path).toDart
        : await native.host.moveEntry(root!, path, parent, name).toDart;
    final metadata = await native.host.readMetadata(root!).toDart;
    await native.host
        .writeMetadata(root!, native.host.moveNotes(metadata, path, to))
        .toDart;
    final current = folder;
    if (current != null &&
        (native.pathKey(current) == prefix ||
            native.pathKey(current).startsWith('$prefix/'))) {
      folder = action == 'trash'
          ? null
          : [...to.toDart, ...current.toDart.skip(path.length)].toJS;
    }
    await refresh();
  }

  Future<void> noteActions(native.Note note) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(note.name),
        actions: [
          if (filter == 'trash')
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'restore'),
              child: const Text('Restore'),
            )
          else ...[
            if (note.conflicts > 0)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, 'conflicts'),
                child: const Text('Compare conflicting versions'),
              ),
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
    } else if (action == 'conflicts') {
      await open(note.path);
      await reviewConflicts(active!);
    } else {
      await relocate(note.path, action);
    }
  }

  Future<void> folderDetails(native.Folder item) async {
    final key = native.pathKey(item.path);
    final values = library!.metadata.folders[key] ?? native.host.emptyFolder();
    final description = TextEditingController(text: values.description);
    final tags = TagEditingController(
      values.tags.toDart.map((tag) => tag.toDart).toList(),
    );
    var paper = values.paper;
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CupertinoAlertDialog(
          title: Text('${item.name} details'),
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
      final metadata = await native.host.readMetadata(root!).toDart;
      metadata.folders[key] = values;
      registerTags(metadata, values.tags);
      await native.host.writeMetadata(root!, metadata).toDart;
      await refresh();
    }
    description.dispose();
    tags.dispose();
  }

  Future<void> folderActions(native.Folder item) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(item.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'details'),
            child: const Text('Details and tags'),
          ),
          if (item.path.length > 0) ...[
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
    if (action == 'details')
      await folderDetails(item);
    else
      await relocate(item.path, action);
  }

  String modifiedLabel(double milliseconds) =>
      'Modified ${DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt()).toLocal().toString().substring(0, 16)}';

  Future<void> open(JSArray<JSString> path) async {
    if (captures.isNotEmpty)
      throw StateError('Complete the drawing before switching notes.');
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

  Future<void> followLink(native.OpenNote source, String href, int page) async {
    final uri = Uri.parse(href);
    if (uri.hasScheme) {
      if (!{'https', 'http', 'mailto'}.contains(uri.scheme))
        throw StateError('This link protocol is not supported.');
      web.window.open(uri.toString(), '_blank', 'noopener,noreferrer');
      return;
    }
    final pages = source.document.navigation().toDart;
    final file = pages
        .firstWhere((m) => m.page == page && m.id.isEmpty && m.href.isEmpty)
        .file;
    final base = Uri(
      scheme: 'https',
      host: 'notes.invalid',
      pathSegments: [
        ...source.path.toDart.map((s) => s.toDart),
        ...file.split('/'),
      ],
    );
    final target = base.resolveUri(uri);
    if (target.host != base.host ||
        target.scheme != base.scheme ||
        target.hasQuery)
      throw StateError('Choose a page in the notes folder.');
    final parts = target.pathSegments;
    if (parts.length < 3 ||
        parts[parts.length - 2] != 'pages' ||
        !parts.last.endsWith('.svg'))
      throw StateError('The link must name a notebook page.');
    final path = parts.take(parts.length - 2).map((s) => s.toJS).toList().toJS;
    await open(path);
    setState(() => rightFocused = false);
    destination.value = null;
    destination.value = (
      noteKey: native.pathKey(path),
      file: 'pages/${parts.last}',
      id: target.fragment,
    );
  }

  Future<String?> chooseNotebookLink(native.OpenNote source, int page) async {
    final note = await chooseNote();
    if (note == null || !mounted) return null;
    final existing = opened
        .where((n) => native.pathKey(n.path) == native.pathKey(note.path))
        .firstOrNull;
    final target =
        existing ??
        await native.host.openNotebook(engine!, root!, note.path).toDart;
    try {
      if (!mounted) return null;
      final mark = await chooseDestination(context, target.document);
      if (mark == null) return null;
      final sourceFile = source.document
          .navigation()
          .toDart
          .firstWhere((m) => m.page == page && m.href.isEmpty && m.id.isEmpty)
          .file;
      final from = paths.posix.dirname(
        paths.posix.joinAll([
          ...source.path.toDart.map((p) => p.toDart),
          sourceFile,
        ]),
      );
      final to = paths.posix.joinAll([
        ...note.path.toDart.map((p) => p.toDart),
        mark.file,
      ]);
      return Uri(
        pathSegments: paths.posix.relative(to, from: from).split('/'),
        fragment: mark.id.isEmpty ? null : mark.id,
      ).toString();
    } finally {
      if (existing == null) target.document.free();
    }
  }

  Future<void> reviewConflicts(native.OpenNote note) async {
    if (captures.isNotEmpty)
      throw StateError('Complete the drawing before comparing versions.');
    var conflicts =
        (await native.host.noteConflicts(engine!, note.dir).toDart).toDart;
    try {
      await note.saver.save().toDart;
    } catch (_) {
      conflicts =
          (await native.host.noteConflicts(engine!, note.dir).toDart).toDart;
      if (conflicts.isEmpty) rethrow;
    }
    if (conflicts.isEmpty) return;
    var changed = false;
    while (conflicts.isNotEmpty && mounted) {
      final conflict = conflicts.first;
      final choice = await compareVersions(context, conflict);
      if (choice == null) break;
      await native.host
          .resolveConflict(engine!, note.dir, conflict, choice)
          .toDart;
      await note.saver
          .resolved(
            conflict.original,
            conflict.originalBytes,
            conflict.copyBytes,
          )
          .toDart;
      changed = true;
      conflicts =
          (await native.host.noteConflicts(engine!, note.dir).toDart).toDart;
    }
    if (!changed) return;
    final path = note.path;
    setState(() {
      releaseNotes([note]);
      opened.remove(note);
      tab = opened.isEmpty ? 0 : tab.clamp(0, opened.length - 1);
    });
    await WidgetsBinding.instance.endOfFrame;
    await open(path);
    await refresh();
  }

  Future<void> importPdf() => run(() async {
    try {
      final note = await native.host
          .importPdf(
            engine!,
            root!,
            folder!,
            ((JSNumber completed, JSNumber total) {
              if (mounted)
                setState(
                  () => confirmation =
                      'Importing PDF: ${completed.toDartInt} / ${total.toDartInt} pages',
                );
            }).toJS,
          )
          .toDart;
      if (note != null) setState(() => active = note);
    } finally {
      await refresh();
    }
  });

  Future<void> closeNote(int index) async {
    final note = opened[index];
    if (captures.contains(native.pathKey(note.path)))
      throw StateError('Complete the drawing before closing this note.');
    await note.saver.save().toDart;
    setState(() {
      releaseNotes([note]);
      opened.removeAt(index);
      if (index < tab) tab--;
      tab = opened.isEmpty ? 0 : tab.clamp(0, opened.length - 1);
      if (opened.isEmpty) inLibrary = true;
    });
    await refresh();
  }

  Future<void> create(bool isFolder) async {
    setState(() => confirmation = null);
    final metadata = library!.metadata;
    final defaults =
        metadata.folders[native.pathKey(folder ?? <JSString>[].toJS)] ??
        native.host.emptyFolder();
    final draft = isFolder ? null : metadata.draft;
    final title = TextEditingController(text: draft?.title ?? '');
    final description = TextEditingController();
    final tags = TagEditingController(
      (draft?.tags ?? defaults.tags).toDart.map((tag) => tag.toDart).toList(),
    );
    final templateName = TextEditingController();
    var target = draft?.folder ?? folder ?? <JSString>[].toJS;
    var paper = draft?.template ?? defaults.paper;
    var size = draft?.pageSize ?? 'a4';
    var orientation = draft?.orientation ?? 'portrait';
    var coverColor = defaults.coverColor;
    var coverStyle = defaults.coverStyle;
    final accepted = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CreationSheet(
          title: isFolder ? 'New Notebook' : 'New Note',
          preview: PaperPreview(
            engine: engine!,
            root: root!,
            paper: paper,
            size: size,
            orientation: orientation,
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
              TagEditor(controller: tags),
              CupertinoButton(
                onPressed: () async {
                  final selected = await showCupertinoModalPopup<native.Folder>(
                    context: context,
                    builder: (context) => CupertinoActionSheet(
                      title: Text(
                        isFolder ? 'Choose location' : 'Choose notebook',
                      ),
                      actions: [
                        for (final item in library!.folders.toDart)
                          CupertinoActionSheetAction(
                            onPressed: () => Navigator.pop(context, item),
                            child: Text(
                              native.pathKey(item.path).isEmpty
                                  ? 'My Notes'
                                  : native.pathKey(item.path),
                            ),
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
                  '${isFolder ? 'Location' : 'Notebook'}: ${native.pathKey(target).isEmpty ? 'My Notes' : native.pathKey(target)}',
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
                const SizedBox(height: 12),
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
                for (final settings in metadata.startingTemplates.toDart)
                  CupertinoButton(
                    onPressed: () => update(() {
                      target = settings.folder;
                      paper = settings.paper;
                      size = settings.pageSize;
                      orientation = settings.orientation ?? 'portrait';
                      tags.replace(
                        settings.tags.toDart.map((tag) => tag.toDart).toList(),
                      );
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
    final chosenTags = tags.tags.map((tag) => tag.toJS).toList().toJS;
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
          orientation: orientation,
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
            orientation: orientation,
            tags: chosenTags,
          ),
        ].toJS;
        await native.host.writeMetadata(root!, current).toDart;
        await refresh();
        setState(() => confirmation = 'Template saved');
        return;
      }
      if (isFolder) {
        final created = await native.host
            .createFolder(root!, target, name)
            .toDart;
        folder = created;
        final values = native.host.emptyFolder();
        values.description = descriptionText;
        values.paper = paper;
        values.coverColor = coverColor;
        values.coverStyle = coverStyle;
        values.tags = chosenTags;
        current.folders[native.pathKey(created)] = values;
      } else {
        active = await native.host
            .createNotebook(
              engine!,
              root!,
              target,
              name,
              paper,
              size,
              orientation,
            )
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
    releaseNotes(opened.toList());
    panes.dispose();
    viewport.dispose();
    destination.dispose();
    search.dispose();
    observer?.disconnect();
    changes?.cancel();
    super.dispose();
  }

  void showTabs(bool hidden) {
    web.window.localStorage.setItem('tabBar', hidden ? 'hidden' : 'top');
    setState(() => tabsHidden = hidden);
  }

  List<PullDownMenuEntry> workspaceMenu() => [
    PullDownMenuItem(
      title: tabsHidden ? 'Show tab bar' : 'Hide tab bar',
      onTap: () => showTabs(!tabsHidden),
    ),
    PullDownMenuItem(
      title: secondary == null ? 'Split view' : 'Close split view',
      onTap: () => run(splitNote),
    ),
    if (secondary != null) ...[
      PullDownMenuItem.selectable(
        title: 'Link views',
        selected: linkedViews,
        onTap: () => setState(() => linkedViews = !linkedViews),
      ),
      PullDownMenuItem(
        title: 'Rotate split',
        onTap: () => setState(
          () => splitAxis = splitAxis == Axis.horizontal
              ? Axis.vertical
              : Axis.horizontal,
        ),
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: active == null ? 0 : 1,
      children: [
        ExcludeFocus(excluding: !inLibrary, child: buildLibrary(context)),
        Column(
          children: [
            if (!tabsHidden)
              ColoredBox(
                color: chromeBar,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (var i = 0; i < opened.length; i++)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: tab == i ? selectedFill : chromeBar,
                                    border: const Border(
                                      right: BorderSide(color: chrome),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CupertinoButton(
                                        onPressed: () =>
                                            run(() => open(opened[i].path)),
                                        child: Text(opened[i].name),
                                      ),
                                      CupertinoButton(
                                        onPressed: () =>
                                            run(() => closeNote(i)),
                                        child: Semantics(
                                          label: 'Close ${opened[i].name}',
                                          child: const Icon(
                                            CupertinoIcons.xmark,
                                            size: 16,
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
                      CupertinoButton(
                        onPressed: () => run(pickNote),
                        child: Semantics(
                          label: 'Open note',
                          child: const Icon(CupertinoIcons.add),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: MultiSplitView(
                controller: panes,
                axis: splitAxis,
                builder: (context, area) => area.index == 0
                    ? Listener(
                        onPointerDown: (_) {
                          if (rightFocused)
                            setState(() => rightFocused = false);
                        },
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
                                    destination: destination,
                                    workspaceMenu: workspaceMenu,
                                    onFollowLink: (href, page) =>
                                        followLink(opened[i], href, page),
                                    onChooseNotebookLink: (page) =>
                                        chooseNotebookLink(opened[i], page),
                                    viewport: viewport,
                                    linked:
                                        secondary != null &&
                                        linkedViews &&
                                        i == tab,
                                    engine: engine!,
                                    active:
                                        !inLibrary && i == tab && !rightFocused,
                                    onCaptureChanged: (value) => setState(() {
                                      final key = native.pathKey(
                                        opened[i].path,
                                      );
                                      if (value)
                                        captures.add(key);
                                      else
                                        captures.remove(key);
                                    }),
                                    onLibrary: showLibrary,
                                    onConflicts: () =>
                                        run(() => reviewConflicts(opened[i])),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : Listener(
                        onPointerDown: (_) {
                          if (!rightFocused)
                            setState(() => rightFocused = true);
                        },
                        child: Column(
                          children: [
                            CupertinoButton(
                              onPressed: () => run(chooseReference),
                              child: Text('Reference: ${secondaryNote!.name}'),
                            ),
                            Expanded(
                              child: TickerMode(
                                enabled: !inLibrary,
                                child: ExcludeFocus(
                                  excluding: inLibrary,
                                  child: Notebook(
                                    key: ValueKey('reference-$secondary'),
                                    note: secondaryNote!,
                                    destination: destination,
                                    workspaceMenu: workspaceMenu,
                                    onFollowLink: (href, page) =>
                                        followLink(secondaryNote!, href, page),
                                    onChooseNotebookLink: (page) =>
                                        chooseNotebookLink(
                                          secondaryNote!,
                                          page,
                                        ),
                                    engine: engine!,
                                    viewport: viewport,
                                    linked: linkedViews,
                                    active: !inLibrary && rightFocused,
                                    onLibrary: showLibrary,
                                    onConflicts: () => run(
                                      () => reviewConflicts(secondaryNote!),
                                    ),
                                    onCaptureChanged: (value) => setState(() {
                                      if (value)
                                        captures.add(secondary!);
                                      else
                                        captures.remove(secondary);
                                    }),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pickNote() async {
    final note = await chooseNote();
    if (note != null) await open(note.path);
  }

  Future<native.Note?> chooseNote() async {
    await refresh();
    if (!mounted) return null;
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
                              title: Text(noteTitle(note)),
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
    return picked;
  }

  String count(int number, String noun) =>
      '$number $noun${number == 1 ? '' : 's'}';

  Color hexColor(String value) =>
      Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);

  // Sorts by the chosen field and direction. Ascending is A to Z for names
  // and oldest first for modification times.
  List<T> ordered<T>(
    Iterable<T> items,
    String Function(T) name,
    double Function(T) modified,
  ) => items.toList()
    ..sort((a, b) {
      final order = sort == 'name'
          ? name(a).toLowerCase().compareTo(name(b).toLowerCase())
          : modified(a).compareTo(modified(b));
      return ascending ? order : -order;
    });

  native.FolderMetadata folderMetadata(native.Folder item) =>
      library!.metadata.folders[native.pathKey(item.path)] ??
      native.host.emptyFolder();

  Widget tagList(Iterable<String> names) {
    final tags = library!.metadata.tags.toDart;
    return Wrap(
      spacing: 8,
      children: [
        for (final name in names)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.circle_fill,
                size: 8,
                color: hexColor(
                  tags.where((tag) => tag.name == name).firstOrNull?.color ??
                      '#8E8E93',
                ),
              ),
              const SizedBox(width: 4),
              Text(name, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }

  Widget actionsButton(String label, Future<void> Function() actions) =>
      CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        onPressed: () => run(actions),
        child: Semantics(
          label: label,
          child: const Icon(CupertinoIcons.ellipsis_circle),
        ),
      );

  // The whole card or row is one tap target.
  Widget tappable(String label, VoidCallback onTap, Widget child) => Semantics(
    label: label,
    button: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    ),
  );

  Widget cover(native.Folder item, {bool titled = true}) {
    final metadata = folderMetadata(item);
    final color = hexColor(metadata.coverColor);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: metadata.coverStyle == 'spine'
            ? Border(
                left: BorderSide(
                  color: Color.lerp(color, const Color(0xFF000000), 0.3)!,
                  width: 10,
                ),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: titled
              ? Text(
                  item.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  String notebookSummary(native.Folder item) => item.notes.length == 0
      ? 'No notes'
      : '${count(item.notes.length, 'note')} · ${modifiedLabel(item.modified)}';

  Widget notebookCard(native.Folder item) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return tappable(
      'Open ${item.name}',
      () => setState(() => folder = item.path),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cover(item)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.notes.length == 0
                      ? 'No notes'
                      : count(item.notes.length, 'note'),
                ),
              ),
              actionsButton(
                '${item.name} notebook actions',
                () => folderActions(item),
              ),
            ],
          ),
          if (item.notes.length > 0)
            Text(
              modifiedLabel(item.modified),
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          tagList(folderMetadata(item).tags.toDart.map((tag) => tag.toDart)),
        ],
      ),
    );
  }

  Widget notebookRow(native.Folder item) => tappable(
    'Open ${item.name}',
    () => setState(() => folder = item.path),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 48, height: 64, child: cover(item, titled: false)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  notebookSummary(item),
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                tagList(
                  folderMetadata(item).tags.toDart.map((tag) => tag.toDart),
                ),
              ],
            ),
          ),
          actionsButton(
            '${item.name} notebook actions',
            () => folderActions(item),
          ),
        ],
      ),
    ),
  );

  // `place` names the notebook when the list mixes notes from many notebooks.
  Widget noteCard(native.Note item, String? place) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return tappable(
      'Open ${item.name}',
      () => run(() => filter == 'trash' ? noteActions(item) : open(item.path)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: NoteThumbnail(engine: engine!, root: root!, note: item),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  noteTitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              actionsButton('${item.name} actions', () => noteActions(item)),
            ],
          ),
          Text(
            [?place, modifiedLabel(item.modified)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          tagList(noteMetadata(item).tags.toDart.map((tag) => tag.toDart)),
        ],
      ),
    );
  }

  Widget noteRow(native.Note item, String? place) => tappable(
    'Open ${item.name}',
    () => run(() => filter == 'trash' ? noteActions(item) : open(item.path)),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 64,
            child: NoteThumbnail(engine: engine!, root: root!, note: item),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  noteTitle(item),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [?place, modifiedLabel(item.modified)].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                tagList(
                  noteMetadata(item).tags.toDart.map((tag) => tag.toDart),
                ),
              ],
            ),
          ),
          actionsButton('${item.name} actions', () => noteActions(item)),
        ],
      ),
    ),
  );

  List<Widget> section(String heading, List<Widget> items, double aspect) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(
          heading,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    if (grid)
      SliverGrid.extent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 24,
        crossAxisSpacing: 20,
        childAspectRatio: aspect,
        children: items,
      )
    else
      SliverList.list(children: items),
    const SliverToBoxAdapter(child: SizedBox(height: 24)),
  ];

  Widget menu(
    String label,
    IconData icon,
    List<PullDownMenuEntry> Function() items,
  ) => PullDownButton(
    itemBuilder: (_) => items(),
    buttonBuilder: (context, showMenu) => CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      onPressed: showMenu,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), const SizedBox(width: 6), Text(label)],
      ),
    ),
  );

  List<PullDownMenuEntry> sortMenu() => [
    for (final (value, title) in const [
      ('name', 'Name'),
      ('modified', 'Date modified'),
    ])
      PullDownMenuItem.selectable(
        title: title,
        selected: sort == value,
        onTap: () => setState(() {
          sort = value;
          ascending = value == 'name';
        }),
      ),
    const PullDownMenuDivider.large(),
    for (final (value, title)
        in sort == 'name'
            ? const [(true, 'A to Z'), (false, 'Z to A')]
            : const [(false, 'Newest first'), (true, 'Oldest first')])
      PullDownMenuItem.selectable(
        title: title,
        selected: ascending == value,
        onTap: () => setState(() => ascending = value),
      ),
    const PullDownMenuDivider.large(),
    for (final (value, title) in const [(true, 'Grid'), (false, 'List')])
      PullDownMenuItem.selectable(
        title: title,
        selected: grid == value,
        onTap: () => setState(() => grid = value),
      ),
  ];

  String get filterLabel => switch (filter) {
    'favorites' => 'Favorites',
    'trash' => 'Trash',
    'tag' => selectedTag!,
    _ => 'All',
  };

  List<PullDownMenuEntry> filterMenu() => [
    for (final (value, title) in const [
      ('all', 'All'),
      ('favorites', 'Favorites'),
      ('trash', 'Trash'),
    ])
      PullDownMenuItem.selectable(
        title: title,
        selected: filter == value,
        onTap: () => setState(() => filter = value),
      ),
    if (library!.metadata.tags.length > 0) ...[
      const PullDownMenuDivider.large(),
      const PullDownMenuTitle(title: Text('Tags')),
      for (final tag in library!.metadata.tags.toDart)
        PullDownMenuItem.selectable(
          title: tag.name,
          iconWidget: Icon(
            CupertinoIcons.circle_fill,
            size: 12,
            color: hexColor(tag.color),
          ),
          selected: filter == 'tag' && selectedTag == tag.name,
          onTap: () => setState(() {
            filter = 'tag';
            selectedTag = tag.name;
          }),
        ),
    ],
  ];

  List<PullDownMenuEntry> settingsMenu() => [
    PullDownMenuItem(title: 'New tag', onTap: () => run(addTag)),
    PullDownMenuItem(
      title: 'Choose notes folder',
      onTap: () => run(chooseRoot),
    ),
  ];

  bool hasTag(JSArray<JSString> tags) =>
      tags.toDart.any((tag) => tag.toDart == selectedTag);

  bool matches(Iterable<String> texts, String query) =>
      texts.any((text) => text.toLowerCase().contains(query));

  // The Notebooks view. The filter picks which notebooks and notes show,
  // the search narrows them, and the sort orders them.
  List<Widget> notebooksContent() {
    final query = search.text.trim().toLowerCase();
    String tagText(JSArray<JSString> tags) =>
        tags.toDart.map((tag) => tag.toDart).join(' ');
    final places = {
      for (final item in library!.folders.toDart)
        for (final note in item.notes.toDart)
          native.pathKey(note.path): item.name,
    };
    final notebooks = filter == 'all' || filter == 'tag'
        ? library!.folders.toDart.where((item) {
            if (item.path.length == 0 && item.notes.length == 0) return false;
            final metadata = folderMetadata(item);
            if (filter == 'tag' && !hasTag(metadata.tags)) return false;
            return matches([
              item.name,
              metadata.description,
              tagText(metadata.tags),
              ...item.notes.toDart.map((note) => note.name),
            ], query);
          })
        : <native.Folder>[];
    final notes =
        switch (filter) {
          'trash' => library!.trash.toDart,
          'all' when query.isEmpty => <native.Note>[],
          _ => library!.folders.toDart.expand((item) => item.notes.toDart),
        }.where((note) {
          final metadata = noteMetadata(note);
          if (filter == 'favorites' && !metadata.favorite) return false;
          if (filter == 'tag' && !hasTag(metadata.tags)) return false;
          return matches([
            note.name,
            metadata.description,
            tagText(metadata.tags),
          ], query);
        });
    final shownNotebooks = ordered(
      notebooks,
      (item) => item.name,
      (item) => item.modified,
    );
    final shownNotes = ordered(
      notes,
      (item) => item.name,
      (item) => item.modified,
    );
    if (shownNotebooks.isEmpty && shownNotes.isEmpty)
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              query.isNotEmpty
                  ? 'Nothing matches "${search.text.trim()}".'
                  : switch (filter) {
                      'favorites' => 'No favorite notes.',
                      'trash' => 'The trash is empty.',
                      'tag' => 'Nothing has the tag $selectedTag.',
                      _ => 'No notebooks. Tap New Notebook to make one.',
                    },
            ),
          ),
        ),
      ];
    return [
      if (shownNotebooks.isNotEmpty)
        ...section(count(shownNotebooks.length, 'notebook'), [
          for (final item in shownNotebooks)
            grid ? notebookCard(item) : notebookRow(item),
        ], 0.62),
      if (shownNotes.isNotEmpty)
        ...section(count(shownNotes.length, 'note'), [
          for (final item in shownNotes)
            grid
                ? noteCard(item, places[native.pathKey(item.path)])
                : noteRow(item, places[native.pathKey(item.path)]),
        ], 0.6),
    ];
  }

  List<Widget> notebookContent(native.Folder item) {
    final metadata = folderMetadata(item);
    final notes = ordered(
      item.notes.toDart,
      (note) => note.name,
      (note) => note.modified,
    );
    return [
      if (metadata.description.isNotEmpty || metadata.tags.length > 0)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (metadata.description.isNotEmpty) Text(metadata.description),
                const SizedBox(height: 8),
                tagList(metadata.tags.toDart.map((tag) => tag.toDart)),
              ],
            ),
          ),
        ),
      if (notes.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text('No notes. Tap New Note to write the first one.'),
          ),
        )
      else
        ...section(count(notes.length, 'note'), [
          for (final note in notes)
            grid ? noteCard(note, null) : noteRow(note, null),
        ], 0.6),
    ];
  }

  Widget buildLibrary(BuildContext context) {
    final connected = root != null && !reconnect && library != null;
    final notebook = connected && folder != null
        ? library!.folders.toDart
              .where(
                (item) => native.pathKey(item.path) == native.pathKey(folder!),
              )
              .firstOrNull
        : null;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: notebook == null
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => folder = null),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.chevron_left),
                    Text('Notebooks'),
                  ],
                ),
              ),
        middle: Text(notebook?.name ?? 'Notebooks'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) const CupertinoActivityIndicator(),
            if (connected && notebook != null)
              actionsButton(
                '${notebook.name} notebook actions',
                () => folderActions(notebook),
              ),
            if (connected && notebook == null)
              PullDownButton(
                itemBuilder: (_) => settingsMenu(),
                buttonBuilder: (context, showMenu) => CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: showMenu,
                  child: Semantics(
                    label: 'Settings',
                    child: const Icon(CupertinoIcons.settings),
                  ),
                ),
              ),
          ],
        ),
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
            Expanded(
              child: connected
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (notebook == null) ...[
                                Expanded(
                                  child: CupertinoSearchTextField(
                                    controller: search,
                                    placeholder: 'Search notebooks and notes',
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                menu(
                                  filterLabel,
                                  CupertinoIcons.line_horizontal_3_decrease,
                                  filterMenu,
                                ),
                              ] else
                                const Spacer(),
                              menu(
                                'Sort',
                                CupertinoIcons.arrow_up_arrow_down,
                                sortMenu,
                              ),
                              const SizedBox(width: 8),
                              if (notebook == null)
                                CupertinoButton.filled(
                                  onPressed: busy ? null : () => create(true),
                                  child: const Text('New Notebook'),
                                )
                              else ...[
                                CupertinoButton(
                                  onPressed: busy ? null : importPdf,
                                  child: const Text('Import PDF'),
                                ),
                                CupertinoButton.filled(
                                  onPressed: busy ? null : () => create(false),
                                  child: const Text('New Note'),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: CustomScrollView(
                              slivers: notebook == null
                                  ? notebooksContent()
                                  : notebookContent(notebook),
                            ),
                          ),
                        ],
                      ),
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
                                await watch();
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
