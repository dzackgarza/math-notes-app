import 'dart:ui';

import 'package:flutter/cupertino.dart';

import 'notes_ui.dart' show HoverTint;
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

// A sheet's surface: CupertinoPopupSurface on surface2. Cupertino's own
// fill is a translucent gray (_kDialogColor in
// flutter/lib/src/cupertino/dialog.dart).
class ModalSurface extends StatelessWidget {
  const ModalSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CupertinoPopupSurface(
    isSurfacePainted: false,
    child: ColoredBox(color: surface2, child: child),
  );
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

// An alert and an action sheet on surface2. CupertinoAlertDialog and
// CupertinoActionSheet paint _kDialogColor with no theme hook, and their
// actions take taps only through the parent's slide gesture. The layout and
// semantics follow those widgets (flutter/lib/src/cupertino/dialog.dart):
// a 270 px alert with 14 px corners, 45 px action rows, two actions side by
// side and more stacked; a sheet as wide as the shorter screen side, with
// 8 px margins, 57 px action rows, and the cancel button in its own group.
// An action is a CupertinoButton, so it keeps the press fade, focus, and
// keyboard activation; the slide across actions to choose one is absent.
const _alertWidth = 270.0;
const _cornerRadius = BorderRadius.all(Radius.circular(14));
const _alertActionHeight = 45.0;
const _sheetActionHeight = 57.0;
const _sheetMargin = 8.0;

Widget _divider({bool vertical = false}) => vertical
    ? const SizedBox(width: 0.5, child: ColoredBox(color: separator))
    : const SizedBox(height: 0.5, child: ColoredBox(color: separator));

class Alert extends StatelessWidget {
  const Alert({super.key, this.title, this.content, required this.actions});

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final buttons = actions.length == 2
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: actions[0]),
                _divider(vertical: true),
                Expanded(child: actions[1]),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, action) in actions.indexed) ...[
                if (i > 0) _divider(),
                action,
              ],
            ],
          );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: SizedBox(
          width: _alertWidth,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: surface2,
              borderRadius: _cornerRadius,
              boxShadow: modalShadow,
            ),
            child: ClipRRect(
              borderRadius: _cornerRadius,
              child: Semantics(
                role: SemanticsRole.alertDialog,
                namesRoute: true,
                scopesRoute: true,
                explicitChildNodes: true,
                label: 'Alert',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 19, 16, 19),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (title != null)
                              DefaultTextStyle(
                                style: headline.copyWith(color: label),
                                textAlign: TextAlign.center,
                                child: title!,
                              ),
                            if (title != null && content != null)
                              const SizedBox(height: 4),
                            if (content != null)
                              DefaultTextStyle(
                                style: footnote.copyWith(color: label),
                                textAlign: TextAlign.center,
                                child: content!,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (actions.isNotEmpty) ...[_divider(), buttons],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.height,
    required this.onPressed,
    required this.child,
    required this.isDefaultAction,
    required this.isDestructiveAction,
  });

  final double height;
  final VoidCallback? onPressed;
  final Widget child;
  final bool isDefaultAction;
  final bool isDestructiveAction;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? tertiaryLabel
        : isDestructiveAction
        ? destructive
        : accentText;
    final style = (isDefaultAction ? headline : body).copyWith(color: color);
    // A disabled CupertinoButton still exposes an enabled tap action.
    return Semantics(
      enabled: onPressed != null,
      child: HoverTint(
        radius: 0,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size(0, height),
          borderRadius: BorderRadius.zero,
          onPressed: onPressed,
          child: DefaultTextStyle(
            style: style,
            textAlign: TextAlign.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

class AlertAction extends StatelessWidget {
  const AlertAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool isDefaultAction;
  final bool isDestructiveAction;

  @override
  Widget build(BuildContext context) => _Action(
    height: _alertActionHeight,
    onPressed: onPressed,
    isDefaultAction: isDefaultAction,
    isDestructiveAction: isDestructiveAction,
    child: child,
  );
}

class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.onPressed,
    required this.child,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool isDefaultAction;
  final bool isDestructiveAction;

  @override
  Widget build(BuildContext context) => _Action(
    height: _sheetActionHeight,
    onPressed: onPressed,
    isDefaultAction: isDefaultAction,
    isDestructiveAction: isDestructiveAction,
    child: child,
  );
}

class ActionSheet extends StatelessWidget {
  const ActionSheet({
    super.key,
    this.title,
    this.message,
    this.actions = const [],
    this.cancelButton,
  });

  final Widget? title;
  final Widget? message;
  final List<Widget> actions;
  final Widget? cancelButton;

  Widget group(List<Widget> children) => DecoratedBox(
    decoration: const BoxDecoration(
      color: surface2,
      borderRadius: _cornerRadius,
      boxShadow: modalShadow,
    ),
    child: ClipRRect(
      borderRadius: _cornerRadius,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.shortestSide - _sheetMargin * 2;
    final header = title != null || message != null;
    return SafeArea(
      minimum: const EdgeInsets.all(_sheetMargin),
      child: Semantics(
        role: SemanticsRole.dialog,
        namesRoute: true,
        scopesRoute: true,
        explicitChildNodes: true,
        label: 'Alert',
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: group([
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (header)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13.5,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (title != null)
                                      DefaultTextStyle(
                                        style: subhead.copyWith(
                                          color: secondaryLabel,
                                        ),
                                        textAlign: TextAlign.center,
                                        child: title!,
                                      ),
                                    if (title != null && message != null)
                                      const SizedBox(height: 4),
                                    if (message != null)
                                      DefaultTextStyle(
                                        style: footnote.copyWith(
                                          color: secondaryLabel,
                                        ),
                                        textAlign: TextAlign.center,
                                        child: message!,
                                      ),
                                  ],
                                ),
                              ),
                            for (final (i, action) in actions.indexed) ...[
                              if (header || i > 0) _divider(),
                              action,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
                if (cancelButton != null) ...[
                  const SizedBox(height: _sheetMargin),
                  group([cancelButton!]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
