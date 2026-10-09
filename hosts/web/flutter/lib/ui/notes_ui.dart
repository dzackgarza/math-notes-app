import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../conflict_sheet.dart';
import '../data/notes_folder.dart';
import '../data/open_notes.dart';
import '../host.dart' as native;
import '../note_thumbnail.dart';
import 'modal.dart';
import 'theme.dart';

String noteTitle(native.Note note) =>
    note.conflicts > 0 ? '⚠ ${note.name}' : note.name;

// "Today 14:47", "Yesterday 09:05", or "1 Oct 2026".
String modifiedLabel(double milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt());
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  final clock = DateFormat.Hm().format(time);
  return switch (days) {
    0 => 'Today $clock',
    1 => 'Yesterday $clock',
    _ => DateFormat.yMMMd().format(time),
  };
}

// A card or row that is one tap target: Tab focuses it, Enter or Space
// activates it, and focus and hover show on it. `onTap` receives the
// target's context.
class TapTarget extends StatefulWidget {
  const TapTarget({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
  });
  final String label;
  final void Function(BuildContext) onTap;
  final Widget child;
  final bool selected;

  @override
  State<TapTarget> createState() => _TapTargetState();
}

class _TapTargetState extends State<TapTarget> {
  var focused = false;
  var hovered = false;

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    button: true,
    selected: widget.selected,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => focused = value),
      onShowHoverHighlight: (value) => setState(() => hovered = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(context),
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(context),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: focused ? Border.all(color: accentText, width: 2) : null,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: hovered ? separator : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

// A hover tint behind a button. CupertinoButton shows press and focus but
// not hover, which a pointer on the web and on the iPad needs.
// A CupertinoButton with its enabled state in the semantics tree. Its own
// Semantics sets only the button flag, and its tap recognizer stays
// registered while it is disabled, so the web engine exposes a disabled
// button as tappable (TRAPS.md).
Widget withEnabledState(CupertinoButton button) =>
    Semantics(enabled: button.enabled, child: button);

class HoverTint extends StatefulWidget {
  const HoverTint({super.key, required this.child, this.radius = 10});
  final Widget child;
  final double radius;

  @override
  State<HoverTint> createState() => _HoverTintState();
}

class _HoverTintState extends State<HoverTint> {
  var hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: hovered ? separator : null,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: widget.child,
    ),
  );
}

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
                    color: secondaryLabel,
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
  final picked = await showModalSheet<native.Note>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => ModalSurface(
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Open note', style: headline),
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
  } on JSObject catch (error) {
    // The save wrote the local versions as conflict copies.
    if (!error.instanceof(native.host.externalChangesError)) rethrow;
    conflicts = await folder.conflicts(note.dir);
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
