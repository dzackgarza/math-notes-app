import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:toastification/toastification.dart';
import 'package:web/web.dart' as web;

import 'activity.dart';
import 'data/app_preferences.dart';
import 'data/notes_folder.dart';
import 'data/open_notes.dart';
import 'errors.dart';
import 'host.dart' as native;
import 'ui/library/library_screen.dart';
import 'ui/library/library_view_model.dart';
import 'ui/editor/tools_view_model.dart';
import 'ui/theme.dart';
import 'ui/workspace/workspace_screen.dart';

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    showError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    showError(error, stack);
    return true;
  };
  web.window.addEventListener(
    'unhandledrejection',
    ((web.PromiseRejectionEvent event) => showError(
      event.reason.dartify() ?? 'A promise failed.',
    )).toJS,
  );
  web.window.addEventListener(
    'error',
    ((web.ErrorEvent event) => showError(event.message)).toJS,
  );
  runApp(const MathNotes());
  SemanticsBinding.instance.ensureSemantics();
}

class MathNotes extends StatelessWidget {
  const MathNotes({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => Activity()),
      ChangeNotifierProvider(create: (_) => AppPreferences()),
      ChangeNotifierProvider(create: (_) => NotesFolder()),
      ChangeNotifierProvider(create: (_) => ToolsViewModel()),
      ChangeNotifierProvider(
        create: (context) => OpenNotes(context.read<NotesFolder>()),
      ),
      ChangeNotifierProvider(
        create: (context) => LibraryViewModel(
          context.read<NotesFolder>(),
          context.read<OpenNotes>(),
        ),
      ),
    ],
    child: Consumer<AppPreferences>(
      builder: (context, preferences, child) {
        setAppearance(preferences.darkAppearance);
        return ToastificationWrapper(
          child: CupertinoApp(
            title: 'Math Notes',
            theme: cupertinoTheme,
            builder: (context, child) =>
                PullDownButtonInheritedTheme(data: pullDownTheme, child: child!),
            home: const Shell(),
          ),
        );
      },
    ),
  );
}

// The library, or the workspace while a note is open. The workspace stays
// built under the library so open notes keep their state.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  @override
  void initState() {
    super.initState();
    final folder = context.read<NotesFolder>();
    unawaited(
      context.read<Activity>().run(() async {
        native.host.checkPlatform();
        // The offline cache fills in the background; the app does not wait
        // for it.
        unawaited(
          deadline(
            'Saving the app for offline use',
            const Duration(minutes: 2),
            native.host.cacheApp().toDart,
          ).then((_) {}, onError: showError),
        );
        await folder.start();
        if (!mounted) return;
        final preferences = context.read<AppPreferences>();
        final last = web.window.localStorage.getItem('lastNote');
        if (preferences.reopenLastNote && folder.connected && last != null) {
          final exists = folder.library!.folders.toDart
              .expand((item) => item.notes.toDart)
              .any((note) => native.pathKey(note.path) == last);
          if (exists) {
            await context.read<OpenNotes>().open(
              last.split('/').map((part) => part.toJS).toList().toJS,
            );
          } else {
            showError('The last note is unavailable. Open it from the library.');
          }
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppPreferences>();
    final session = context.watch<OpenNotes>();
    return IndexedStack(
      index: session.active == null ? 0 : 1,
      children: [
        ExcludeFocus(
          excluding: !session.inLibrary,
          child: LibraryScreen(),
        ),
        WorkspaceScreen(),
      ],
    );
  }
}
