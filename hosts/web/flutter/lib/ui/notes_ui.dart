import 'dart:js_interop';

import 'package:flutter/cupertino.dart';

import '../conflict_sheet.dart';
import '../data/notes_folder.dart';
import '../data/open_notes.dart';
import '../host.dart' as native;
import '../note_thumbnail.dart';

String noteTitle(native.Note note) =>
    note.conflicts > 0 ? '⚠ ${note.name}' : note.name;

String modifiedLabel(double milliseconds) =>
    'Modified ${DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt()).toLocal().toString().substring(0, 16)}';

// A searchable list of every note in the notes folder; null when the user
// cancels.
Future<native.Note?> chooseNote(
  BuildContext context,
  NotesFolder folder,
) async {
  await folder.refresh();
  if (!context.mounted) return null;
  final filter = TextEditingController();
  final picked = await showCupertinoModalPopup<native.Note>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => CupertinoPopupSurface(
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Open note'),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: CupertinoSearchTextField(
                    controller: filter,
                    onChanged: (_) => update(() {}),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final item in folder.library!.folders.toDart)
                        for (final note in item.notes.toDart.where(
                          (note) => note.name.toLowerCase().contains(
                            filter.text.toLowerCase(),
                          ),
                        ))
                          CupertinoListTile(
                            title: Text(noteTitle(note)),
                            leadingSize: 48,
                            leading: NoteThumbnail(
                              engine: folder.engine!,
                              root: folder.root!,
                              note: note,
                            ),
                            subtitle: Text(item.name),
                            onTap: () => Navigator.pop(context, note),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  filter.dispose();
  return picked;
}

// Shows each conflicting copy of `note` beside the original until the user
// resolves all of them or cancels. A resolution changes the note's files, so
// the note opens again from them.
Future<void> reviewConflicts(
  BuildContext context,
  NotesFolder folder,
  OpenNotes session,
  native.OpenNote note,
) async {
  session.requireNoCapture('comparing versions');
  var conflicts = await folder.conflicts(note.dir);
  try {
    await note.saver.save().toDart;
  } catch (_) {
    conflicts = await folder.conflicts(note.dir);
    if (conflicts.isEmpty) rethrow;
  }
  var changed = false;
  while (conflicts.isNotEmpty && context.mounted) {
    final conflict = conflicts.first;
    final choice = await compareVersions(context, conflict);
    if (choice == null) break;
    await folder.resolveConflict(note.dir, conflict, choice);
    await note.saver
        .resolved(conflict.original, conflict.originalBytes, conflict.copyBytes)
        .toDart;
    changed = true;
    conflicts = await folder.conflicts(note.dir);
  }
  if (changed) await session.reload(note);
}
