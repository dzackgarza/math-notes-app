import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

// Typed representations of the existing TypeScript host boundary.
@JS('mathNotes')
external Host get host;

// JavaScript promises resolve void operations with undefined.
typedef VoidResult = JSAny?;

extension type Directory(JSObject value) implements JSObject {}

extension type Engine(JSObject value) implements JSObject {}

extension type StartRoot(JSObject value) implements JSObject {
  external Directory? get root;
  external bool get needsGesture;
}

extension type Note(JSObject value) implements JSObject {
  external String get name;
  external JSArray<JSString> get path;
  external double get modified;
  external int get conflicts;
}

extension type Folder(JSObject value) implements JSObject {
  external String get name;
  external JSArray<JSString> get path;
  external JSArray<Note> get notes;
  external double get modified;
}

extension type Tag(JSObject value) implements JSObject {
  external factory Tag.create({String name, String color});
  external String get name;
  external String get color;
}

extension type Library(JSObject value) implements JSObject {
  external JSArray<Folder> get folders;
  external JSArray<Note> get trash;
  external JSArray<JSString> get templates;
  external LibraryMetadata get metadata;
}

extension type MetadataMap<T extends JSObject>(JSObject value)
    implements JSObject {
  T? operator [](String key) => getProperty<T?>(key.toJS);
  void operator []=(String key, T entry) => setProperty(key.toJS, entry);
}

extension type NoteMetadata(JSObject value) implements JSObject {
  external bool get favorite;
  external set favorite(bool value);
  external String get description;
  external set description(String value);
  external JSArray<JSString> get tags;
  external set tags(JSArray<JSString> value);
}

extension type FolderMetadata(JSObject value) implements JSObject {
  external String get description;
  external set description(String value);
  external String get paper;
  external set paper(String value);
  external String get coverColor;
  external set coverColor(String value);
  external String get coverStyle;
  external set coverStyle(String value);
  external JSArray<JSString> get tags;
  external set tags(JSArray<JSString> value);
}

extension type LibraryMetadata(JSObject value) implements JSObject {
  external JSArray<Tag> get tags;
  external set tags(JSArray<Tag> value);
  external MetadataMap<NoteMetadata> get notes;
  external MetadataMap<FolderMetadata> get folders;
  external JSArray<StartingTemplate> get startingTemplates;
  external set startingTemplates(JSArray<StartingTemplate> value);
  external NoteDraft? get draft;
  external set draft(NoteDraft value);
  void clearDraft() => delete('draft'.toJS);
}

extension type NoteDraft(JSObject value) implements JSObject {
  external factory NoteDraft.create({
    JSArray<JSString> folder,
    String title,
    String template,
    JSArray<JSString> tags,
    String pageSize,
  });
  external JSArray<JSString> get folder;
  external String get title;
  external String get template;
  external JSArray<JSString> get tags;
  external String? get pageSize;
}

extension type StartingTemplate(JSObject value) implements JSObject {
  external factory StartingTemplate.create({
    String name,
    JSArray<JSString> folder,
    String paper,
    String pageSize,
    JSArray<JSString> tags,
  });
  external String get name;
  external JSArray<JSString> get folder;
  external String get paper;
  external String get pageSize;
  external JSArray<JSString> get tags;
}

extension type Size(JSObject value) implements JSObject {
  external double get width;
  external double get height;
}

extension type PageRect(JSObject value) implements JSObject {
  external double get x;
  external double get y;
  external double get width;
  external double get height;
}

extension type ToolSettings(JSObject value) implements JSObject {
  external factory ToolSettings.create({
    int brush,
    int rgb,
    double size,
    double opacity,
  });
  external int get brush;
  external int get rgb;
  external double get size;
  external double get opacity;
}

extension type Pen(JSObject value) implements JSObject {
  external factory Pen.create({String id, String name, ToolSettings tool});
  external String get id;
  external String get name;
  external ToolSettings get tool;
}

extension type SaveState(JSObject value) implements JSObject {
  external String get status;
  external String? get message;
}

extension type Saver(JSObject value) implements JSObject {
  external SaveState get state;
  external void schedule();
  external JSPromise<VoidResult> save();
  external JSPromise<VoidResult> resolved(
    String path,
    JSUint8Array original,
    JSUint8Array copy,
  );
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type HistoryStep(JSObject value) implements JSObject {
  external int get page;
}

extension type Selection(JSObject value) implements JSObject {
  external int get count;
  external int get page;
  external double get x;
  external double get y;
  external double get width;
  external double get height;
}

extension type Layer(JSObject value) implements JSObject {
  external String get id;
  external String get name;
  external bool get hidden;
  external bool get locked;
}

extension type Document(JSObject value) implements JSObject {
  external JSArray<Layer> layers();
  external void addLayer(String name);
  external void setLayer(int index, String name, bool hidden, bool locked);
  external void moveLayer(int from, int to);
  external void removeLayer(int index, bool mergeDown);
  external int pageCount();
  external void insertPage(int index);
  external void deletePage(int index);
  external void movePage(int from, int to);
  external void setPageSize(int size);
  external Size contentSize();
  external PageRect pageRect(int index);
  external HistoryStep? undo();
  external HistoryStep? redo();
  external void free();
}

extension type Canvas(JSObject value) implements JSObject {
  external int activeLayer();
  external void setLayer(int index);
  external void beginFigure(int page);
  external String selectedFigure();
  external void setView(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
  );
  external void setSurfaceSize(double width, double height, double ratio);
  external void setTool(ToolSettings tool);
  external void setEraser(int kind, bool active);
  external void setSelector(int kind, bool active);
  external int pageAt(double x, double y);
  external Selection? selection();
  external void selectAll(int page);
  external void clearSelection();
  external void deleteSelection();
  external String copySelection(bool cut);
  external void paste(String svg, double x, double y);
  external void duplicateSelection();
  external void insertText(String value, double x, double y);
  external bool selectTextAt(double x, double y);
  external String selectedText();
  external void setSelectedText(String value);
  external bool render();
  external void free();
}

extension type OpenNote(JSObject value) implements JSObject {
  external Directory get dir;
  external String get template;
  external set template(String value);
  external String get name;
  external JSArray<JSString> get path;
  external Directory get root;
  external Document get document;
  external Saver get saver;
}

extension type NoteConflict(JSObject value) implements JSObject {
  external JSUint8Array get originalBytes;
  external JSUint8Array get copyBytes;
  external String get original;
  external String get copy;
  external String get provider;
  external bool get notebook;
  external bool get page;
  external JSUint8Array? get left;
  external JSUint8Array? get right;
  external String get leftSummary;
  external String get rightSummary;
}

extension type Host(JSObject value) implements JSObject {
  external JSPromise<JSArray<NoteConflict>> noteConflicts(
    Engine engine,
    Directory dir,
  );
  external JSPromise<VoidResult> resolveConflict(
    Engine engine,
    Directory dir,
    NoteConflict conflict,
    String choice,
  );
  external JSPromise<VoidResult> applyTemplate(
    Directory root,
    Document document,
    String name,
  );
  external JSPromise<JSArray<JSString>> listTemplates(Directory root);
  external String finishFigure(Canvas canvas);
  external String figureSource(OpenNote note, Canvas canvas, bool capturing);
  external JSPromise<JSUint8Array?> thumbnail(
    Engine engine,
    Directory root,
    Note note,
  );
  external JSArray<JSString> get tagColors;
  external JSPromise<JSUint8Array> paperPreview(
    Engine engine,
    Directory root,
    String paper,
    String size,
  );
  external JSPromise<VoidResult> cacheApp();
  external void exportPdf(
    OpenNote note,
    int first,
    int count,
    JSArray<JSString> layers,
  );
  external JSPromise<JSBoolean> insertImage(
    OpenNote note,
    Canvas canvas,
    int page,
    double x,
    double y,
  );
  external JSPromise<Engine> loadEngine();
  external JSPromise<StartRoot> startRoot();
  external JSPromise<Directory> pickRoot();
  external JSPromise<JSBoolean> requestPermission(Directory root);
  external JSPromise<Library> library(Directory root, Engine engine);
  external NoteMetadata emptyNote();
  external FolderMetadata emptyFolder();
  external JSPromise<LibraryMetadata> readMetadata(Directory root);
  external JSPromise<VoidResult> writeMetadata(
    Directory root,
    LibraryMetadata metadata,
  );
  external LibraryMetadata moveNotes(
    LibraryMetadata metadata,
    JSArray<JSString> from,
    JSArray<JSString> to,
  );
  external JSPromise<JSArray<JSString>> moveEntry(
    Directory root,
    JSArray<JSString> from,
    JSArray<JSString> parent,
    String name,
  );
  external JSPromise<JSArray<JSString>> moveToTrash(
    Directory root,
    JSArray<JSString> path,
  );
  external JSPromise<JSArray<JSString>> createFolder(
    Directory root,
    JSArray<JSString> parent,
    String name,
  );
  external JSPromise<OpenNote> createNotebook(
    Engine engine,
    Directory root,
    JSArray<JSString> parent,
    String name,
    String template,
    String size,
  );
  external JSPromise<OpenNote> openNotebook(
    Engine engine,
    Directory root,
    JSArray<JSString> path,
  );
  external JSPromise<OpenNote?> importPdf(
    Engine engine,
    Directory root,
    JSArray<JSString> parent,
    JSFunction progress,
  );
  external JSPromise<JSArray<Pen>> readPens(Directory root, Engine engine);
  external JSPromise<VoidResult> writePens(
    Directory root,
    Engine engine,
    JSArray<Pen> pens,
  );
  external JSPromise<Canvas> mountCanvas(
    OpenNote note,
    web.HTMLCanvasElement canvas,
  );
  external bool acceptPen(
    Canvas canvas,
    web.HTMLCanvasElement element,
    double stamp,
  );
}

String pathKey(JSArray<JSString> path) =>
    path.toDart.map((part) => part.toDart).join('/');
