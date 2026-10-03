import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import '../../data/notes_folder.dart';
import '../../data/open_notes.dart';
import '../../host.dart' as native;

// The values of the creation form for a notebook or a note.
typedef CreationForm = ({
  // 'create', 'draft' or 'template'.
  String action,
  String name,
  JSArray<JSString> tags,
  String description,
  String settingsName,
  JSArray<JSString> target,
  String paper,
  String size,
  String orientation,
  String coverColor,
  String coverStyle,
});

// The state of the library screen: which notebook is open, and which
// notebooks and notes the filter, the search and the sort show.
class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel(this.folder, this.session) {
    folder.addListener(notifyListeners);
    session.addListener(notifyListeners);
  }
  final NotesFolder folder;
  final OpenNotes session;

  // The open notebook; null shows the Notebooks view.
  JSArray<JSString>? notebookPath;
  String? confirmation;
  String filter = 'all';
  String? selectedTag;
  String sort = 'name';
  bool ascending = true;
  bool grid = true;
  String query = '';

  native.Library get library => folder.library!;

  native.Folder? get notebook {
    final path = notebookPath;
    if (!folder.connected || path == null) return null;
    return library.folders.toDart
        .where((item) => native.pathKey(item.path) == native.pathKey(path))
        .firstOrNull;
  }

  void showNotebook(JSArray<JSString>? path) {
    notebookPath = path;
    notifyListeners();
  }

  void setFilter(String value, [String? tag]) {
    filter = value;
    selectedTag = tag;
    if (value == 'recent') {
      sort = 'modified';
      ascending = false;
    }
    notifyListeners();
  }

  void setSort(String value) {
    sort = value;
    ascending = value == 'name';
    notifyListeners();
  }

  void setAscending(bool value) {
    ascending = value;
    notifyListeners();
  }

  void setGrid(bool value) {
    grid = value;
    notifyListeners();
  }

  void setQuery(String value) {
    query = value.trim();
    notifyListeners();
  }

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

  bool hasTag(JSArray<JSString> tags) =>
      tags.toDart.any((tag) => tag.toDart == selectedTag);

  bool matches(Iterable<String> texts) {
    final lower = query.toLowerCase();
    return texts.any((text) => text.toLowerCase().contains(lower));
  }

  static String tagText(JSArray<JSString> tags) =>
      tags.toDart.map((tag) => tag.toDart).join(' ');

  // The notebook name of each note, for lists that mix notebooks.
  Map<String, String> get places => {
    for (final item in library.folders.toDart)
      for (final note in item.notes.toDart)
        native.pathKey(note.path): item.name,
  };

  // The Notebooks view. The filter picks which notebooks and notes show,
  // the search narrows them, and the sort orders them.
  List<native.Folder> get shownNotebooks => ordered(
    filter == 'all' || filter == 'tag'
        ? library.folders.toDart.where((item) {
            if (item.path.length == 0 && item.notes.length == 0) return false;
            final metadata = folder.folderMetadata(item.path);
            if (filter == 'tag' && !hasTag(metadata.tags)) return false;
            return matches([
              item.name,
              metadata.description,
              tagText(metadata.tags),
              ...item.notes.toDart.map((note) => note.name),
            ]);
          })
        : <native.Folder>[],
    (item) => item.name,
    (item) => item.modified,
  );

  List<native.Note> get shownNotes => ordered(
    switch (filter) {
      'trash' => library.trash.toDart,
      'recent' => library.folders.toDart.expand((item) => item.notes.toDart),
      'all' when query.isEmpty => <native.Note>[],
      _ => library.folders.toDart.expand((item) => item.notes.toDart),
    }.where((note) {
      final metadata = folder.noteMetadata(note);
      if (filter == 'favorites' && !metadata.favorite) return false;
      if (filter == 'tag' && !hasTag(metadata.tags)) return false;
      return matches([note.name, metadata.description, tagText(metadata.tags)]);
    }),
    (item) => item.name,
    (item) => item.modified,
  );

  Future<void> toggleFavorite(native.Note note) {
    final metadata = folder.noteMetadata(note);
    metadata.favorite = !metadata.favorite;
    return folder.saveNote(note, metadata);
  }

  // Moves `path` into `parent` as `name`; a null parent moves it to the
  // trash. The open notes inside it close first, and the open notebook
  // follows the move.
  Future<void> relocate(
    JSArray<JSString> path,
    JSArray<JSString>? parent,
    String name,
  ) async {
    await session.closeUnder(path);
    final to = await folder.move(path, parent, name);
    final prefix = native.pathKey(path);
    final current = notebookPath;
    if (current == null) return;
    final key = native.pathKey(current);
    if (key != prefix && !key.startsWith('$prefix/')) return;
    showNotebook(
      parent == null
          ? null
          : [...to.toDart, ...current.toDart.skip(path.length)].toJS,
    );
  }

  Future<void> chooseRoot() async {
    final chosen = await folder.pick();
    await session.closeAll();
    notebookPath = null;
    await folder.connect(chosen);
  }

  Future<void> importPdf() async {
    final note = await folder.importPdf(notebookPath!, (completed, total) {
      confirmation = 'Importing PDF: $completed / $total pages';
      notifyListeners();
    });
    if (note != null) session.show(note);
  }

  // The form starts from the metadata that the open notes last saved.
  Future<void> prepareCreation() async {
    confirmation = null;
    notifyListeners();
    await session.saveAll();
    await folder.refresh();
  }

  Future<void> create(bool isFolder, CreationForm form) async {
    switch (form.action) {
      case 'draft':
        await folder.updateMetadata((metadata) {
          NotesFolder.registerTags(metadata, form.tags);
          metadata.draft = native.NoteDraft.create(
            folder: form.target,
            title: form.name,
            template: form.paper,
            tags: form.tags,
            pageSize: form.size,
            orientation: form.orientation,
          );
        });
        confirmation = 'Draft saved';
        notifyListeners();
      case 'template':
        await folder.updateMetadata((metadata) {
          NotesFolder.registerTags(metadata, form.tags);
          metadata.startingTemplates = [
            ...metadata.startingTemplates.toDart.where(
              (item) => item.name != form.settingsName,
            ),
            native.StartingTemplate.create(
              name: form.settingsName,
              folder: form.target,
              paper: form.paper,
              pageSize: form.size,
              orientation: form.orientation,
              tags: form.tags,
            ),
          ].toJS;
        });
        confirmation = 'Template saved';
        notifyListeners();
      case 'create' when isFolder:
        final values = native.host.emptyFolder();
        values.description = form.description;
        values.paper = form.paper;
        values.coverColor = form.coverColor;
        values.coverStyle = form.coverStyle;
        values.tags = form.tags;
        showNotebook(await folder.createFolder(form.target, form.name, values));
      case 'create':
        session.show(
          await folder.createNotebook(
            form.target,
            form.name,
            form.paper,
            form.size,
            form.orientation,
            form.tags,
          ),
        );
    }
  }

  @override
  void dispose() {
    folder.removeListener(notifyListeners);
    session.removeListener(notifyListeners);
    super.dispose();
  }
}
