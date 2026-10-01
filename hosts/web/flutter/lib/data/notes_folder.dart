import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import '../activity.dart';
import '../errors.dart';
import '../host.dart' as native;

// The repository for the notes folder: the engine, the folder handle, and the
// library read from it. Changes to the folder go through a queue, so two
// read-modify-write changes of the library metadata never interleave.
class NotesFolder extends ChangeNotifier {
  native.Engine? engine;
  native.Directory? root;
  native.Library? library;
  // The saved folder needs a user gesture to grant permission again.
  bool reconnect = false;
  // False while a note is open: the library reads the folder again on return.
  bool following = true;
  // True once start has read the saved folder. A folder chosen before then
  // would be replaced by the saved one.
  bool started = false;

  bool get connected => root != null && !reconnect && library != null;

  Future<void> start() async {
    engine = await deadline(
      'Loading the engine',
      const Duration(seconds: 30),
      native.host.loadEngine().toDart,
    );
    notifyListeners();
    final start = await deadline(
      'Opening the saved notes folder',
      const Duration(seconds: 30),
      native.host.startRoot().toDart,
    );
    root = start.root;
    reconnect = start.needsGesture;
    started = true;
    notifyListeners();
    final saved = root;
    if (saved != null && !reconnect) await connect(saved);
  }

  Future<native.Directory> pick() => native.host.pickRoot().toDart;

  Future<void> grantPermission() async {
    final granted = await native.host.requestPermission(root!).toDart;
    if (!granted.toDart)
      throw StateError(
        'Folder permission was denied. Reconnect to open your notes.',
      );
    await connect(root!);
  }

  Future<void> connect(native.Directory chosen) async {
    root = chosen;
    reconnect = false;
    library = null;
    notifyListeners();
    await deadline(
      'Preparing the notes folder',
      const Duration(seconds: 30),
      native.host.prepareRoot(chosen, engine!).toDart,
    );
    await watch();
    await refresh();
  }

  // Reads overlap when the user acts during a read. Only the newest read
  // replaces the library, so an older read cannot show stale notes.
  int reads = 0;
  Future<void> refresh() async {
    final read = ++reads;
    final result = await deadline(
      'Reading the notes folder',
      const Duration(seconds: 60),
      native.host.library(root!).toDart,
    );
    if (read != reads) return;
    library = result;
    notifyListeners();
  }

  // The library follows the notes folder. A change from this app or from
  // another program (for example a sync client) reads the folder again.
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
              if (following) refresh().then((_) {}, onError: showError);
            });
          }).toJS,
        )
        .toDart;
  }

  Future<void> queue = Future.value();
  Future<T> serial<T>(Future<T> Function() task) {
    final result = queue.then((_) => task());
    queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  native.NoteMetadata noteMetadata(native.Note note) =>
      library!.metadata.notes[native.pathKey(note.path)] ??
      native.host.emptyNote();

  native.FolderMetadata folderMetadata(JSArray<JSString> path) =>
      library!.metadata.folders[native.pathKey(path)] ??
      native.host.emptyFolder();

  // Reads the metadata file, applies `change`, writes it, and reads the
  // library again.
  Future<void> updateMetadata(void Function(native.LibraryMetadata) change) =>
      serial(() async {
        final metadata = await native.host.readMetadata(root!).toDart;
        change(metadata);
        await native.host.writeMetadata(root!, metadata).toDart;
      }).then((_) => refresh());

  // Adds each unknown tag name with the next palette color.
  static void registerTags(
    native.LibraryMetadata metadata,
    JSArray<JSString> names,
  ) {
    final tags = metadata.tags.toDart.toList();
    final colors = native.host.tagColors.toDart;
    for (final name in names.toDart) {
      if (tags.any((tag) => tag.name == name.toDart)) continue;
      tags.add(
        native.Tag.create(
          name: name.toDart,
          color: colors[tags.length % colors.length].toDart,
        ),
      );
    }
    metadata.tags = tags.toJS;
  }

  Future<void> addTag(String name, String color) => updateMetadata((metadata) {
    if (metadata.tags.toDart.any((tag) => tag.name == name))
      throw StateError('This tag name is already in use.');
    metadata.tags = [
      ...metadata.tags.toDart,
      native.Tag.create(name: name, color: color),
    ].toJS;
  });

  Future<void> saveNote(native.Note note, native.NoteMetadata values) =>
      updateMetadata((metadata) {
        metadata.notes[native.pathKey(note.path)] = values;
        registerTags(metadata, values.tags);
      });

  Future<void> saveFolder(
    JSArray<JSString> path,
    native.FolderMetadata values,
  ) => updateMetadata((metadata) {
    metadata.folders[native.pathKey(path)] = values;
    registerTags(metadata, values.tags);
  });

  // Moves or trashes an entry and carries its notes' metadata to the new
  // path. Returns the new path.
  Future<JSArray<JSString>> move(
    JSArray<JSString> path,
    JSArray<JSString>? parent,
    String name,
  ) async {
    final to = await serial(() async {
      final to = parent == null
          ? await native.host.moveToTrash(root!, path).toDart
          : await native.host.moveEntry(root!, path, parent, name).toDart;
      final metadata = await native.host.readMetadata(root!).toDart;
      await native.host
          .writeMetadata(root!, native.host.moveNotes(metadata, path, to))
          .toDart;
      return to;
    });
    await refresh();
    return to;
  }

  Future<JSArray<JSString>> createFolder(
    JSArray<JSString> parent,
    String name,
    native.FolderMetadata values,
  ) async {
    final created = await serial(
      () => native.host.createFolder(root!, parent, name).toDart,
    );
    await saveFolder(created, values);
    return created;
  }

  Future<native.OpenNote> createNotebook(
    JSArray<JSString> parent,
    String name,
    String paper,
    String size,
    String orientation,
    JSArray<JSString> tags,
  ) async {
    final note = await serial(
      () => native.host
          .createNotebook(
            engine!,
            root!,
            parent,
            name,
            paper,
            size,
            orientation,
          )
          .toDart,
    );
    await updateMetadata((metadata) {
      final values = native.host.emptyNote();
      values.tags = tags;
      metadata.notes[native.pathKey(note.path)] = values;
      registerTags(metadata, tags);
      metadata.clearDraft();
    });
    return note;
  }

  Future<native.OpenNote> open(JSArray<JSString> path) => deadline(
    'Opening ${path.toDart.last.toDart}',
    const Duration(seconds: 30),
    native.host.openNotebook(engine!, root!, path).toDart,
  );

  Future<native.OpenNote?> importPdf(
    JSArray<JSString> parent,
    void Function(int completed, int total) progress,
  ) async {
    try {
      return await serial(
        () => native.host
            .importPdf(
              engine!,
              root!,
              parent,
              ((JSNumber completed, JSNumber total) => progress(
                completed.toDartInt,
                total.toDartInt,
              )).toJS,
            )
            .toDart,
      );
    } finally {
      await refresh();
    }
  }

  Future<List<native.NoteConflict>> conflicts(native.Directory dir) async =>
      (await native.host.noteConflicts(engine!, dir).toDart).toDart;

  Future<void> resolveConflict(
    native.Directory dir,
    native.NoteConflict conflict,
    String choice,
  ) => serial(
    () => native.host.resolveConflict(engine!, dir, conflict, choice).toDart,
  );

  @override
  void dispose() {
    observer?.disconnect();
    changes?.cancel();
    super.dispose();
  }
}
