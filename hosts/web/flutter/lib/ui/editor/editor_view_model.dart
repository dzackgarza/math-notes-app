import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:web/web.dart' as web;

import '../../host.dart' as native;

class EditorViewModel extends ChangeNotifier {
  EditorViewModel(this.note) {
    _saveListener = ((web.Event event) => notifyListeners()).toJS;
    note.saver.addEventListener('change', _saveListener);
  }

  final native.OpenNote note;
  late final JSFunction _saveListener;
  native.Canvas? canvas;
  bool clippingsOpen = false;
  List<native.Clipping> clippings = [];
  bool drawing = false;
  final figureText = TextEditingController();
  native.Selection? selection;
  int page = 0;

  String get figureSource => figureText.text;
  set figureSource(String value) {
    if (figureText.text == value) return;
    figureText.text = value;
    notifyListeners();
  }

  String get saveStatus => note.saver.state.status;

  void changed() => notifyListeners();

  @override
  void dispose() {
    note.saver.removeEventListener('change', _saveListener);
    canvas?.free();
    figureText.dispose();
    super.dispose();
  }
}
