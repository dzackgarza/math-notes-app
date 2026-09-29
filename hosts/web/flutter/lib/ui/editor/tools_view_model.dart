import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:web/web.dart' as web;

import '../../host.dart' as native;

const drawingTools = ['pen', 'marker', 'highlighter'];

const toolKinds = [
  ('pen', 'Pen', LucideIcons.penTool),
  ('marker', 'Marker', LucideIcons.brush),
  ('highlighter', 'Highlighter', LucideIcons.highlighter),
  ('eraser', 'Eraser', LucideIcons.eraser),
  ('lasso', 'Lasso', LucideIcons.lasso),
  ('text', 'Text', LucideIcons.type),
  ('image', 'Image', LucideIcons.image),
  ('space', 'Insert space', LucideIcons.moveVertical),
  ('drawing', 'Drawing mode', LucideIcons.spline),
];

class ToolsViewModel extends ChangeNotifier {
  native.PenFile? _pens;
  String _pen = 'pen';
  int _eraser = 0;
  String _tool = 'pen';
  int _selector = 0;
  int _spaceMode = 6;
  bool _fingerDraws = web.window.localStorage.getItem('fingerDraws') == 'true';
  bool _ribbonBottom =
      web.window.localStorage.getItem('ribbonEdge') == 'bottom';
  final Set<String> _hiddenTools = {
    ...?web.window.localStorage.getItem('hiddenTools')?.split(','),
  }..remove('');

  native.PenFile? get pens => _pens;
  set pens(native.PenFile? value) {
    if (identical(_pens, value)) return;
    _pens = value;
    notifyListeners();
  }

  String get pen => _pen;
  set pen(String value) {
    if (_pen == value) return;
    _pen = value;
    notifyListeners();
  }

  native.ToolSettings get penTool => switch (_pen) {
    'marker' => _pens!.marker,
    'highlighter' => _pens!.highlighter,
    _ => _pens!.pen,
  };

  List<int> get palette => [
    for (final color in _pens?.palette.toDart ?? <JSNumber>[]) color.toDartInt,
  ];

  int get eraser => _eraser;
  set eraser(int value) {
    if (_eraser == value) return;
    _eraser = value;
    notifyListeners();
  }

  String get tool => _tool;
  set tool(String value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  int get selector => _selector;
  set selector(int value) {
    if (_selector == value) return;
    _selector = value;
    notifyListeners();
  }

  int get spaceMode => _spaceMode;
  set spaceMode(int value) {
    if (_spaceMode == value) return;
    _spaceMode = value;
    notifyListeners();
  }

  bool get fingerDraws => _fingerDraws;
  set fingerDraws(bool value) {
    if (_fingerDraws == value) return;
    _fingerDraws = value;
    web.window.localStorage.setItem('fingerDraws', '$value');
    notifyListeners();
  }

  bool get ribbonBottom => _ribbonBottom;
  set ribbonBottom(bool value) {
    if (_ribbonBottom == value) return;
    _ribbonBottom = value;
    web.window.localStorage.setItem('ribbonEdge', value ? 'bottom' : 'top');
    notifyListeners();
  }

  Set<String> get hiddenTools => _hiddenTools;

  void setToolVisible(String kind, bool visible) {
    if (visible) {
      _hiddenTools.remove(kind);
    } else {
      _hiddenTools.add(kind);
    }
    web.window.localStorage.setItem('hiddenTools', _hiddenTools.join(','));
    notifyListeners();
  }
}
