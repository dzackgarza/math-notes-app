import 'dart:js_interop';

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
}

extension type Folder(JSObject value) implements JSObject {
  external String get name;
  external JSArray<JSString> get path;
  external JSArray<Note> get notes;
}

extension type Library(JSObject value) implements JSObject {
  external JSArray<Folder> get folders;
  external JSArray<Note> get trash;
  external JSArray<JSString> get templates;
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
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type HistoryStep(JSObject value) implements JSObject {
  external int get page;
}

extension type Document(JSObject value) implements JSObject {
  external int pageCount();
  external void insertPage(int index);
  external void deletePage(int index);
  external void movePage(int from, int to);
  external Size contentSize();
  external PageRect pageRect(int index);
  external HistoryStep? undo();
  external HistoryStep? redo();
  external void free();
}

extension type Canvas(JSObject value) implements JSObject {
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
  external bool render();
  external void free();
}

extension type OpenNote(JSObject value) implements JSObject {
  external String get name;
  external JSArray<JSString> get path;
  external Directory get root;
  external Document get document;
  external Saver get saver;
}

extension type Host(JSObject value) implements JSObject {
  external JSPromise<Engine> loadEngine();
  external JSPromise<StartRoot> startRoot();
  external JSPromise<Directory> pickRoot();
  external JSPromise<JSBoolean> requestPermission(Directory root);
  external JSPromise<Library> library(Directory root, Engine engine);
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
  external JSPromise<JSArray<Pen>> readPens(Directory root, Engine engine);
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
