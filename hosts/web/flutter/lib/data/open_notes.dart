import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:web/web.dart' as web;

import '../activity.dart';
import '../host.dart' as native;
import 'notes_folder.dart';

typedef NotebookViewport = ({double scale, double x, double y, double scroll});
typedef NoteDestination = ({String noteKey, String file, String id});

// The repository for the editing session: the open notes as tabs, the split
// view, and the notes with a drawing capture in progress. Each open note owns
// a document in the engine; the session frees it when the note closes.
class OpenNotes extends ChangeNotifier {
  OpenNotes(this.folder);
  final NotesFolder folder;

  final opened = <native.OpenNote>[];
  int tab = 0;
  bool _inLibrary = true;
  bool get inLibrary => _inLibrary;
  set inLibrary(bool value) {
    _inLibrary = value;
    folder.following = value;
  }

  final captures = <String>{};
  final panes = MultiSplitViewController(areas: [Area(id: 'main')]);
  // The path key of the note in the right pane; null without a split.
  String? secondary;
  bool rightFocused = false;
  Axis splitAxis = Axis.horizontal;
  bool linkedViews = false;
  // The tab bar is shown at the top or hidden; the choice belongs to the
  // device.
  bool tabsHidden = web.window.localStorage.getItem('tabBar') == 'hidden';
  final viewport = ValueNotifier<NotebookViewport?>(null);
  final destination = ValueNotifier<NoteDestination?>(null);

  native.OpenNote? get active =>
      inLibrary || opened.isEmpty ? null : opened[tab];

  native.OpenNote? get secondaryNote => opened
      .where((note) => native.pathKey(note.path) == secondary)
      .firstOrNull;

  native.OpenNote? find(JSArray<JSString> path) => opened
      .where((note) => native.pathKey(note.path) == native.pathKey(path))
      .firstOrNull;

  void requireNoCapture(String action) {
    if (captures.isNotEmpty)
      throw StateError('Complete the drawing before $action.');
  }

  // Shows `note` in a tab; a note that is not open yet gets a new tab.
  void show(native.OpenNote note) {
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
    notifyListeners();
  }

  Future<void> open(JSArray<JSString> path) async {
    requireNoCapture('switching notes');
    final current = active;
    if (current != null)
      await deadline(
        'Saving ${current.name}',
        const Duration(seconds: 30),
        current.saver.save().toDart,
      );
    show(find(path) ?? await folder.open(path));
  }

  // Saves every open note. The list is read before the first await, so a
  // note that opens while the saves run cannot invalidate the iteration.
  Future<void> saveAll() => deadline(
    'Saving the open notes',
    const Duration(seconds: 30),
    Future.wait([for (final note in opened) note.saver.save().toDart]),
  );

  Future<void> showLibrary() async {
    requireNoCapture('returning to the library');
    inLibrary = true;
    notifyListeners();
    await saveAll();
    await folder.refresh();
  }

  void release(List<native.OpenNote> notes) {
    if (notes.any((note) => native.pathKey(note.path) == secondary))
      closeSplit();
    opened.removeWhere(notes.contains);
    tab = opened.isEmpty ? 0 : tab.clamp(0, opened.length - 1);
    if (opened.isEmpty) inLibrary = true;
    notifyListeners();
    // Canvases are disposed in the next frame before their shared document.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final note in notes) note.document.free();
    });
  }

  Future<void> close(int index) async {
    final note = opened[index];
    if (captures.contains(native.pathKey(note.path)))
      throw StateError('Complete the drawing before closing this note.');
    await note.saver.save().toDart;
    if (index < tab) tab--;
    release([note]);
    await folder.refresh();
  }

  Future<void> closeAll() async {
    await saveAll();
    release(opened.toList());
  }

  // Saves and closes every note at `path` or inside it, before the entry
  // moves.
  Future<void> closeUnder(JSArray<JSString> path) async {
    final prefix = native.pathKey(path);
    final affected = opened.where((note) {
      final key = native.pathKey(note.path);
      return key == prefix || key.startsWith('$prefix/');
    }).toList();
    for (final note in affected) await note.saver.save().toDart;
    release(affected);
  }

  // Opens `note` again from its files, after a conflict resolution changed
  // them.
  Future<void> reload(native.OpenNote note) async {
    final path = note.path;
    release([note]);
    await WidgetsBinding.instance.endOfFrame;
    await open(path);
    await folder.refresh();
  }

  void setCapture(String key, bool capturing) {
    if (capturing)
      captures.add(key);
    else
      captures.remove(key);
    notifyListeners();
  }

  void focusRight(bool right) {
    if (rightFocused == right) return;
    rightFocused = right;
    notifyListeners();
  }

  void closeSplit() {
    secondary = null;
    rightFocused = false;
    if (panes.areasCount > 1) panes.removeAreaAt(1);
  }

  void toggleSplit() {
    requireNoCapture('splitting notes');
    if (secondary != null) {
      closeSplit();
    } else {
      secondary = native.pathKey(opened[tab].path);
      panes.addArea(Area(id: 'reference'));
    }
    notifyListeners();
  }

  // Shows `path` in the right pane and keeps the left tab.
  Future<void> showReference(JSArray<JSString> path) async {
    final previous = tab;
    await open(path);
    secondary = native.pathKey(opened[tab].path);
    tab = previous;
    rightFocused = true;
    notifyListeners();
  }

  void toggleLinkedViews() {
    linkedViews = !linkedViews;
    notifyListeners();
  }

  void rotateSplit() {
    splitAxis = splitAxis == Axis.horizontal ? Axis.vertical : Axis.horizontal;
    notifyListeners();
  }

  void hideTabs(bool hidden) {
    web.window.localStorage.setItem('tabBar', hidden ? 'hidden' : 'top');
    tabsHidden = hidden;
    notifyListeners();
  }

  // Follows a link from `source` on `page`: a web link opens in a new browser
  // tab, and a relative link opens a page of a note in the notes folder.
  Future<void> followLink(native.OpenNote source, String href, int page) async {
    final uri = Uri.parse(href);
    if (uri.hasScheme) {
      if (!{'https', 'http', 'mailto'}.contains(uri.scheme))
        throw StateError('This link protocol is not supported.');
      web.window.open(uri.toString(), '_blank', 'noopener,noreferrer');
      return;
    }
    final file = source.document
        .navigation()
        .toDart
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
    focusRight(false);
    destination.value = null;
    destination.value = (
      noteKey: native.pathKey(path),
      file: 'pages/${parts.last}',
      id: target.fragment,
    );
  }

  @override
  void dispose() {
    for (final note in opened) note.document.free();
    panes.dispose();
    viewport.dispose();
    destination.dispose();
    super.dispose();
  }
}
