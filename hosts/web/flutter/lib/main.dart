import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';

import 'host.dart' as native;
import 'notebook.dart';

void main() {
  runApp(const MathNotes());
  SemanticsBinding.instance.ensureSemantics();
}

class MathNotes extends StatelessWidget {
  const MathNotes({super.key});
  @override
  Widget build(BuildContext context) => const CupertinoApp(
    title: 'Math Notes',
    theme: CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: Color(0xFF2F6FEB),
    ),
    home: Workspace(),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  native.Engine? engine;
  native.Directory? root;
  native.Library? library;
  native.OpenNote? active;
  final search = TextEditingController();
  JSArray<JSString> folder = <JSString>[].toJS;
  bool reconnect = false;
  bool busy = true;
  String? failure;

  @override
  void initState() {
    super.initState();
    unawaited(
      run(() async {
        engine = await native.host.loadEngine().toDart;
        final start = await native.host.startRoot().toDart;
        root = start.root;
        reconnect = start.needsGesture;
        if (root != null && !reconnect) await refresh();
      }),
    );
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => failure = error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    library = await native.host.library(root!, engine!).toDart;
  }

  Future<void> open(JSArray<JSString> path) async {
    if (active != null) await active!.saver.save().toDart;
    final note = await native.host.openNotebook(engine!, root!, path).toDart;
    setState(() => active = note);
  }

  Future<void> create(bool isFolder) async {
    final title = TextEditingController();
    String paper = 'dotted';
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CupertinoAlertDialog(
          title: Text(isFolder ? 'New Notebook' : 'New Note'),
          content: Column(
            children: [
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: title,
                placeholder: 'Title',
                autofocus: true,
                onChanged: (_) => update(() {}),
              ),
              if (!isFolder) ...[
                const SizedBox(height: 16),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: paper,
                  children: const {
                    'blank': Text('Plain'),
                    'dotted': Text('Dot'),
                    'grid-medium': Text('Grid'),
                    'lined-medium': Text('Ruled'),
                  },
                  onValueChanged: (value) {
                    if (value != null) update(() => paper = value);
                  },
                ),
              ],
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final name = title.text.trim();
    title.dispose();
    if (accepted != true) return;
    await run(() async {
      if (isFolder) {
        folder = await native.host.createFolder(root!, folder, name).toDart;
      } else {
        active = await native.host
            .createNotebook(engine!, root!, folder, name, paper, 'a4')
            .toDart;
      }
      await refresh();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = active;
    if (note != null) {
      return Notebook(
        key: ValueKey(native.pathKey(note.path)),
        note: note,
        engine: engine!,
        onLibrary: () => run(() async {
          await note.saver.save().toDart;
          setState(() => active = null);
          await refresh();
        }),
      );
    }
    final connected = root != null && !reconnect && library != null;
    final selected = library?.folders.toDart
        .where((item) => native.pathKey(item.path) == native.pathKey(folder))
        .firstOrNull;
    final notes =
        selected?.notes.toDart
            .where(
              (note) =>
                  note.name.toLowerCase().contains(search.text.toLowerCase()),
            )
            .toList() ??
        [];
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Math Notes'),
        trailing: busy ? const CupertinoActivityIndicator() : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (failure != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    failure!,
                    style: const TextStyle(
                      color: CupertinoColors.destructiveRed,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: connected
                  ? Row(
                      children: [
                        SizedBox(
                          width: 240,
                          child: CupertinoListSection(
                            header: const Text('NOTEBOOKS'),
                            children: [
                              for (final item in library!.folders.toDart)
                                CupertinoListTile(
                                  title: Text(item.name),
                                  leading: const Icon(CupertinoIcons.folder),
                                  backgroundColor:
                                      native.pathKey(item.path) ==
                                          native.pathKey(folder)
                                      ? const Color(0xFFE3EBFC)
                                      : null,
                                  onTap: () =>
                                      setState(() => folder = item.path),
                                ),
                              CupertinoListTile(
                                title: const Text('Choose notes folder'),
                                leading: const Icon(CupertinoIcons.folder_open),
                                onTap: () => run(() async {
                                  root = await native.host.pickRoot().toDart;
                                  await refresh();
                                }),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        selected?.name ?? 'Library',
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    CupertinoButton(
                                      onPressed: busy
                                          ? null
                                          : () => create(true),
                                      child: const Text('New Notebook'),
                                    ),
                                    CupertinoButton.filled(
                                      onPressed: busy
                                          ? null
                                          : () => create(false),
                                      child: const Text('New Note'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                CupertinoSearchTextField(
                                  controller: search,
                                  placeholder: 'Search notes',
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      for (final item in notes)
                                        CupertinoListTile.notched(
                                          title: Text(item.name),
                                          leading: const Icon(
                                            CupertinoIcons.doc_text,
                                          ),
                                          trailing:
                                              const CupertinoListTileChevron(),
                                          onTap: () =>
                                              run(() => open(item.path)),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.book, size: 64),
                          const SizedBox(height: 24),
                          const Text(
                            'Your notes live in a folder on this device.',
                          ),
                          const SizedBox(height: 24),
                          if (reconnect)
                            CupertinoButton.filled(
                              onPressed: () => run(() async {
                                final granted = await native.host
                                    .requestPermission(root!)
                                    .toDart;
                                if (!granted.toDart)
                                  throw StateError(
                                    'Folder permission was denied. Reconnect to open your notes.',
                                  );
                                reconnect = false;
                                await refresh();
                              }),
                              child: const Text('Reconnect folder'),
                            ),
                          CupertinoButton(
                            onPressed: engine == null
                                ? null
                                : () => run(() async {
                                    root = await native.host.pickRoot().toDart;
                                    reconnect = false;
                                    await refresh();
                                  }),
                            child: const Text('Choose notes folder'),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
