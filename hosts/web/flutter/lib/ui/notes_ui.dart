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

// A search field with its clear button beside the text field in the
// semantics tree. The suffix button of CupertinoSearchTextField splits the
// semantics node of the text field when it appears, and the web engine then
// replaces the focused input element, which ends the typing:
// https://github.com/flutter/flutter/issues/151980
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.placeholder,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final String? placeholder;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: AlignmentDirectional.centerEnd,
    children: [
      CupertinoSearchTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        suffixMode: OverlayVisibilityMode.never,
        padding: const EdgeInsetsDirectional.fromSTEB(5.5, 8, 30, 8),
        onChanged: onChanged,
      ),
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => controller.text.isEmpty
            ? const SizedBox.shrink()
            : CupertinoButton(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                child: Semantics(
                  label: 'Clear search',
                  child: Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 20,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
      ),
    ],
  );
}

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
                  child: SearchField(
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
