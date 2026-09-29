import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:path/path.dart' as paths;
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';

import '../../activity.dart';
import '../../bookmarks_sheet.dart';
import '../../data/notes_folder.dart';
import '../../data/open_notes.dart';
import '../../host.dart' as native;
import '../editor/editor_screen.dart';
import '../editor/editor_view_model.dart';
import '../theme.dart';
import '../notes_ui.dart';

// The editing workspace: the tab bar and one or two panes of open notes.
class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<OpenNotes>();
    final folder = context.read<NotesFolder>();
    final run = context.read<Activity>().run;

    List<PullDownMenuEntry> workspaceMenu() => [
      PullDownMenuItem(
        title: session.tabsHidden ? 'Show tab bar' : 'Hide tab bar',
        onTap: () => session.hideTabs(!session.tabsHidden),
      ),
      PullDownMenuItem(
        title: session.secondary == null ? 'Split view' : 'Close split view',
        onTap: () => run(() async => session.toggleSplit()),
      ),
      if (session.secondary != null) ...[
        PullDownMenuItem.selectable(
          title: 'Link views',
          selected: session.linkedViews,
          onTap: session.toggleLinkedViews,
        ),
        PullDownMenuItem(title: 'Rotate split', onTap: session.rotateSplit),
      ],
    ];

    // A relative link from `page` of `source` to a destination that the user
    // chooses in another note.
    Future<String?> chooseNotebookLink(native.OpenNote source, int page) async {
      final note = await chooseNote(context, folder);
      if (note == null || !context.mounted) return null;
      final existing = session.find(note.path);
      final target = existing ?? await folder.open(note.path);
      try {
        if (!context.mounted) return null;
        final mark = await chooseDestination(context, target.document);
        if (mark == null) return null;
        final sourceFile = source.document
            .navigation()
            .toDart
            .firstWhere((m) => m.page == page && m.href.isEmpty && m.id.isEmpty)
            .file;
        final from = paths.posix.dirname(
          paths.posix.joinAll([
            ...source.path.toDart.map((p) => p.toDart),
            sourceFile,
          ]),
        );
        final to = paths.posix.joinAll([
          ...note.path.toDart.map((p) => p.toDart),
          mark.file,
        ]);
        return Uri(
          pathSegments: paths.posix.relative(to, from: from).split('/'),
          fragment: mark.id.isEmpty ? null : mark.id,
        ).toString();
      } finally {
        if (existing == null) target.document.free();
      }
    }

    Future<void> pickNote() async {
      final note = await chooseNote(context, folder);
      if (note != null) await session.open(note.path);
    }

    Future<void> chooseReference() async {
      final note = await chooseNote(context, folder);
      if (note != null) await session.showReference(note.path);
    }

    Widget notebook(
      native.OpenNote note, {
      Key? key,
      required bool linked,
      required bool active,
    }) => ChangeNotifierProvider(
      key: key,
      create: (_) => EditorViewModel(note),
      child: EditorScreen(
        key: key,
        note: note,
        destination: session.destination,
        workspaceMenu: workspaceMenu,
        onFollowLink: (href, page) => session.followLink(note, href, page),
        onChooseNotebookLink: (page) => chooseNotebookLink(note, page),
        viewport: session.viewport,
        linked: linked,
        engine: folder.engine!,
        active: active,
        onCaptureChanged: (value) =>
            session.setCapture(native.pathKey(note.path), value),
        onLibrary: () => run(session.showLibrary),
        onConflicts: () =>
            run(() => reviewConflicts(context, folder, session, note)),
      ),
    );

    final opened = session.opened;
    final inLibrary = session.inLibrary;
    return Column(
      children: [
        if (!session.tabsHidden)
          ColoredBox(
            color: chromeBar,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < opened.length; i++)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: session.tab == i
                                    ? selectedFill
                                    : chromeBar,
                                border: const Border(
                                  right: BorderSide(color: chrome),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CupertinoButton(
                                    onPressed: () =>
                                        run(() => session.open(opened[i].path)),
                                    child: Text(opened[i].name),
                                  ),
                                  CupertinoButton(
                                    onPressed: () =>
                                        run(() => session.close(i)),
                                    child: Semantics(
                                      label: 'Close ${opened[i].name}',
                                      child: const Icon(
                                        CupertinoIcons.xmark,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: () => run(pickNote),
                    child: Semantics(
                      label: 'Open note',
                      child: const Icon(CupertinoIcons.add),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: MultiSplitView(
            controller: session.panes,
            axis: session.splitAxis,
            builder: (context, area) => area.index == 0
                ? Listener(
                    onPointerDown: (_) => session.focusRight(false),
                    child: IndexedStack(
                      index: opened.isEmpty ? null : session.tab,
                      children: [
                        for (var i = 0; i < opened.length; i++)
                          TickerMode(
                            key: ValueKey(native.pathKey(opened[i].path)),
                            enabled: !inLibrary && i == session.tab,
                            child: ExcludeFocus(
                              excluding: inLibrary || i != session.tab,
                              child: notebook(
                                opened[i],
                                linked:
                                    session.secondary != null &&
                                    session.linkedViews &&
                                    i == session.tab,
                                active:
                                    !inLibrary &&
                                    i == session.tab &&
                                    !session.rightFocused,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Listener(
                    onPointerDown: (_) => session.focusRight(true),
                    child: Column(
                      children: [
                        CupertinoButton(
                          onPressed: () => run(chooseReference),
                          child: Text(
                            'Reference: ${session.secondaryNote!.name}',
                          ),
                        ),
                        Expanded(
                          child: TickerMode(
                            enabled: !inLibrary,
                            child: ExcludeFocus(
                              excluding: inLibrary,
                              child: notebook(
                                session.secondaryNote!,
                                key: ValueKey('reference-${session.secondary}'),
                                linked: session.linkedViews,
                                active: !inLibrary && session.rightFocused,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
