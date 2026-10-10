import 'dart:js_interop';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/cupertino.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:web/web.dart' as web;

import 'ui/theme.dart';
import 'ui/toast.dart';

// Every failure goes to the browser console with its stack and shows as a
// toast until the user closes it.
void showError(Object error, [StackTrace? stack]) {
  web.console.error('$error${stack == null ? '' : '\n$stack'}'.toJS);
  late final OverlaySupportEntry toast;
  toast = showToast(
    alignment: Alignment.topCenter,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(
              container: true,
              role: SemanticsRole.alert,
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Error', style: subhead.copyWith(color: destructive)),
                  Text(error.toString(), style: callout),
                ],
              ),
            ),
          ),
        ),
        CupertinoButton(
          onPressed: () => toast.dismiss(),
          child: Text('Close', style: subhead),
        ),
      ],
    ),
  );
}
