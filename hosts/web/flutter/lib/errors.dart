import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:toastification/toastification.dart';
import 'package:web/web.dart' as web;

// Every failure goes to the browser console with its stack and shows as a
// toast until the user closes it.
void showError(Object error, [StackTrace? stack]) {
  web.console.error('$error${stack == null ? '' : '\n$stack'}'.toJS);
  toastification.show(
    type: ToastificationType.error,
    style: ToastificationStyle.flatColored,
    alignment: Alignment.topCenter,
    title: const Text('Error'),
    description: Text(error.toString()),
    showProgressBar: false,
    closeOnClick: false,
  );
}
