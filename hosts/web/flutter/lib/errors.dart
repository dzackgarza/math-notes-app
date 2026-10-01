import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:toastification/toastification.dart';
import 'package:web/web.dart' as web;

import 'ui/theme.dart';

// Every failure goes to the browser console with its stack and shows as a
// toast until the user closes it. The toast sits at the bottom, clear of the
// tab strip and the navigation bar, on the surface of the undo toast.
void showError(Object error, [StackTrace? stack]) {
  web.console.error('$error${stack == null ? '' : '\n$stack'}'.toJS);
  toastification.showCustom(
    alignment: Alignment.bottomCenter,
    builder: (context, toast) => Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
        decoration: BoxDecoration(
          color: surface2,
          borderRadius: BorderRadius.circular(12),
          boxShadow: floatingShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Error', style: subhead.copyWith(color: destructive)),
                  Text(error.toString(), style: callout),
                ],
              ),
            ),
            MergeSemantics(
              child: Semantics(
                label: 'Close error',
                button: true,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(44, 44),
                  onPressed: () => toastification.dismiss(toast),
                  child: const Icon(LucideIcons.x, color: label, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
