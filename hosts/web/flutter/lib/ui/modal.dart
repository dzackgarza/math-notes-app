import 'dart:ui';

import 'package:flutter/cupertino.dart';

import 'theme.dart';

// One scrim under every modal route: the background color dimmed
// (docs/specs/tablet-ui.md, Visual style). Under a dialog it also blurs the
// screen, which the dialog blocks. A sheet leaves the page legible beside
// it, so a change the sheet makes shows there. The editor shows a still frame
// of the ink canvas under a route, because a blur does not reach a platform
// view (TRAPS.md).
final _scrimFilter = ImageFilter.blur(sigmaX: 6, sigmaY: 6);

// Escape dismisses a route only when its barrier does (_DismissModalAction in
// flutter/lib/src/widgets/routes.dart). A form that must not close holds a
// PopScope.
class _ScrimDialogRoute<T> extends CupertinoDialogRoute<T> {
  _ScrimDialogRoute({required super.builder, required super.context})
    : super(barrierColor: scrim, barrierDismissible: true);

  @override
  ImageFilter? get filter => _scrimFilter;
}

// showCupertinoDialog with the scrim.
Future<T?> showModalDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => Navigator.of(
  context,
  rootNavigator: true,
).push(_ScrimDialogRoute<T>(builder: builder, context: context));

// showCupertinoModalPopup with the scrim and no blur.
Future<T?> showModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showCupertinoModalPopup<T>(
  context: context,
  builder: builder,
  barrierColor: scrim,
);
