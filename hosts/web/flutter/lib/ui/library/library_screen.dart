import 'dart:js_interop';

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';

import '../../activity.dart';
import '../../data/notes_folder.dart';
import '../../data/open_notes.dart';
import '../../host.dart' as native;
import '../../note_thumbnail.dart';
import '../notes_ui.dart';
import '../settings_sheet.dart';
import '../theme.dart';
import 'library_dialogs.dart';
import 'library_view_model.dart';

String count(int number, String noun) =>
    '$number $noun${number == 1 ? '' : 's'}';

// The library: the Notebooks view, or the notes of one notebook.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  bool libraryExpanded = true;
  bool untaggedExpanded = false;
  bool trashExpanded = false;
  final expandedNotebooks = <String>{};

  LibraryViewModel get vm => context.read<LibraryViewModel>();
  NotesFolder get folder => context.read<NotesFolder>();
  OpenNotes get session => context.read<OpenNotes>();
  Future<void> run(Future<void> Function() action) =>
      context.read<Activity>().run(action);

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  List<PullDownMenuEntry> actionItems(
    List<(String, String)> actions,
    Future<void> Function(String) act,
  ) => [
    for (final (action, title) in actions)
      PullDownMenuItem(
        title: title,
        isDestructive: action == 'trash',
        onTap: () => run(() => act(action)),
      ),
  ];

  List<PullDownMenuEntry> noteMenu(native.Note note) => actionItems(
    vm.filter == 'trash'
        ? const [('restore', 'Restore')]
        : [
            if (note.conflicts > 0)
              ('conflicts', 'Compare conflicting versions'),
            (
              'favorite',
              folder.noteMetadata(note).favorite
                  ? 'Unpin note'
                  : 'Pin note',
            ),
            ('details', 'Details and tags'),
            ('rename', 'Rename'),
            ('move', 'Move'),
            ('trash', 'Move to trash'),
          ],
    (action) => noteAction(note, action),
  );

  List<PullDownMenuEntry> folderMenu(native.Folder item) => actionItems([
    ('details', 'Details and tags'),
    if (item.path.length > 0) ...const [
      ('rename', 'Rename'),
      ('move', 'Move'),
      ('trash', 'Move to trash'),
    ],
  ], (action) => folderAction(item, action));

  Future<void> noteAction(native.Note note, String action) async {
    switch (action) {
      case 'favorite':
        await vm.toggleFavorite(note);
      case 'details':
        final metadata = folder.noteMetadata(note);
        if (await editNoteDetails(context, note.name, metadata))
          await folder.saveNote(note, metadata);
      case 'conflicts':
        await session.open(note.path);
        if (mounted)
          await reviewConflicts(context, folder, session, session.active!);
      default:
        await relocate(note.path, action);
    }
  }

  Future<void> folderAction(native.Folder item, String action) async {
    if (action != 'details') return relocate(item.path, action);
    final values = folder.folderMetadata(item.path);
    if (await editFolderDetails(context, item.name, values))
      await folder.saveFolder(item.path, values);
  }

  // Renames, moves, restores or trashes the entry at `path`.
  Future<void> relocate(JSArray<JSString> path, String action) async {
    var name = path.toDart.last.toDart;
    JSArray<JSString>? parent = path.toDart.sublist(0, path.length - 1).toJS;
    if (action == 'rename') {
      final chosen = await askName(context, name);
      if (chosen == null) return;
      name = chosen;
    }
    if (action == 'move' || action == 'restore') {
      final target = await chooseFolder(
        context,
        'Choose notebook',
        vm.library.folders.toDart,
        (item) => item.name,
      );
      if (target == null) return;
      parent = target.path;
    }
    if (action == 'trash') parent = null;
    await vm.relocate(path, parent, name);
  }

  Future<void> addTag() async {
    final tag = await askNewTag(context);
    if (tag != null) await folder.addTag(tag.name, tag.color);
  }

  Future<void> create(bool isFolder, [JSArray<JSString>? targetNotebook]) async {
    await vm.prepareCreation();
    if (!mounted) return;
    final form = await askCreation(
      context,
      isFolder: isFolder,
      engine: folder.engine!,
      root: folder.root!,
      metadata: vm.library.metadata,
      folders: vm.library.folders.toDart,
      notebook: targetNotebook ?? vm.notebookPath,
      targetNotebook: targetNotebook,
    );
    if (form != null) await vm.create(isFolder, form);
  }

  Widget tagList(Iterable<String> names) {
    final tags = vm.library.metadata.tags.toDart;
    return Wrap(
      spacing: 8,
      children: [
        for (final name in names)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.circle_fill,
                size: 8,
                color: hexColor(
                  tags.where((tag) => tag.name == name).firstOrNull?.color ??
                      '#8E8E93',
                ),
              ),
              const SizedBox(width: 4),
              Text(name, style: footnote.copyWith(color: secondaryLabel)),
            ],
          ),
      ],
    );
  }

  Iterable<String> tagNames(JSArray<JSString> tags) =>
      tags.toDart.map((tag) => tag.toDart);

  bool tagged(JSArray<JSString> tags, String name) =>
      tagNames(tags).contains(name);

  Widget actionsButton(
    String label,
    List<PullDownMenuEntry> Function() items,
  ) => PullDownButton(
    itemBuilder: (_) => items(),
    buttonBuilder: (context, showMenu) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: showMenu,
      child: Semantics(
        label: label,
        child: const Icon(CupertinoIcons.ellipsis_circle),
      ),
    ),
  );

  // A notebook cover with the first page of its first note set into the
  // cloth. A small cover omits the label.
  Widget cover(native.Folder item, {bool titled = true}) {
    final metadata = folder.folderMetadata(item.path);
    final first = item.notes.toDart.firstOrNull;
    return coverArt(
      color: hexColor(metadata.coverColor),
      style: metadata.coverStyle,
      title: titled ? item.name : null,
      page: first != null
          ? ColoredBox(color: paper, child: thumbnail(first))
          : const SizedBox(),
    );
  }

  String notebookSummary(native.Folder item) => item.notes.length == 0
      ? 'No notes'
      : '${count(item.notes.length, 'note')} · ${modifiedLabel(item.modified)}';

  Widget notebookCard(native.Folder item) => TapTarget(
    label: 'Open ${item.name}',
    onTap: (_) => vm.showNotebook(item.path),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The title is on the cover label.
        Expanded(child: cover(item)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                notebookSummary(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: footnote.copyWith(color: secondaryLabel),
              ),
            ),
            actionsButton(
              '${item.name} notebook actions',
              () => folderMenu(item),
            ),
          ],
        ),
        tagList(tagNames(folder.folderMetadata(item.path).tags)),
      ],
    ),
  );

  Widget notebookRow(native.Folder item) => TapTarget(
    label: 'Open ${item.name}',
    onTap: (_) => vm.showNotebook(item.path),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 48, height: 64, child: cover(item, titled: false)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: headline),
                Text(
                  notebookSummary(item),
                  style: footnote.copyWith(color: secondaryLabel),
                ),
                tagList(tagNames(folder.folderMetadata(item.path).tags)),
              ],
            ),
          ),
          actionsButton(
            '${item.name} notebook actions',
            () => folderMenu(item),
          ),
        ],
      ),
    ),
  );

  // A note in the trash shows its menu at the card; any other note opens.
  void tapNote(BuildContext card, native.Note item) {
    if (vm.filter != 'trash') {
      run(() => session.open(item.path));
      return;
    }
    final box = card.findRenderObject()! as RenderBox;
    showPullDownMenu(
      context: card,
      items: noteMenu(item),
      position: box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Widget thumbnail(native.Note item) =>
      NoteThumbnail(engine: folder.engine!, root: folder.root!, note: item);

  // `place` names the notebook when the list mixes notes from many notebooks.
  Widget noteCard(native.Note item, String? place) => TapTarget(
    label: 'Open ${item.name}',
    onTap: (card) => tapNote(card, item),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(6)),
              boxShadow: floatingShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: thumbnail(item),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                noteTitle(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subhead,
              ),
            ),
            actionsButton('${item.name} actions', () => noteMenu(item)),
          ],
        ),
        Text(
          [?place, modifiedLabel(item.modified)].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: footnote.copyWith(color: secondaryLabel),
        ),
        tagList(tagNames(folder.noteMetadata(item).tags)),
      ],
    ),
  );

  Widget noteRow(native.Note item, String? place) => TapTarget(
    label: 'Open ${item.name}',
    onTap: (card) => tapNote(card, item),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 48, height: 64, child: thumbnail(item)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noteTitle(item), style: headline),
                Text(
                  [?place, modifiedLabel(item.modified)].join(' · '),
                  style: footnote.copyWith(color: secondaryLabel),
                ),
                tagList(tagNames(folder.noteMetadata(item).tags)),
              ],
            ),
          ),
          actionsButton('${item.name} actions', () => noteMenu(item)),
        ],
      ),
    ),
  );

  List<Widget> section(String heading, List<Widget> items, double aspect) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(heading, style: callout.copyWith(color: secondaryLabel)),
      ),
    ),
    if (vm.grid)
      SliverGrid.extent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 24,
        crossAxisSpacing: 20,
        childAspectRatio: aspect,
        children: items,
      )
    else
      SliverList.list(children: items),
    const SliverToBoxAdapter(child: SizedBox(height: 24)),
  ];

  Widget menu(
    String label,
    IconData icon,
    List<PullDownMenuEntry> Function() items,
  ) => PullDownButton(
    itemBuilder: (_) => items(),
    buttonBuilder: (context, showMenu) => CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      onPressed: showMenu,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), const SizedBox(width: 6), Text(label)],
      ),
    ),
  );

  List<PullDownMenuEntry> sortMenu() => [
    for (final (value, title) in const [
      ('name', 'Name'),
      ('modified', 'Date modified'),
    ])
      PullDownMenuItem.selectable(
        title: title,
        selected: vm.sort == value,
        onTap: () => vm.setSort(value),
      ),
    const GroupRule(),
    for (final (value, title)
        in vm.sort == 'name'
            ? const [(true, 'A to Z'), (false, 'Z to A')]
            : const [(false, 'Newest first'), (true, 'Oldest first')])
      PullDownMenuItem.selectable(
        title: title,
        selected: vm.ascending == value,
        onTap: () => vm.setAscending(value),
      ),
    const GroupRule(),
    for (final (value, title) in const [(true, 'Grid'), (false, 'List')])
      PullDownMenuItem.selectable(
        title: title,
        selected: vm.grid == value,
        onTap: () => vm.setGrid(value),
      ),
  ];

  String get filterLabel => switch (vm.filter) {
    'favorites' => 'Pinned',
    'recent' => 'Recent',
    'trash' => 'Trash',
    'tag' => vm.selectedTag!,
    _ => 'All',
  };

  // The shelf heading names the sidebar row that is selected.
  String get heading => vm.query.isNotEmpty
      ? 'Search'
      : vm.filter == 'all'
      ? 'Library'
      : filterLabel;

  List<PullDownMenuEntry> filterMenu() => [
    for (final (value, title) in const [
      ('all', 'All'),
      ('recent', 'Recent'),
      ('favorites', 'Pinned'),
      ('trash', 'Trash'),
    ])
      PullDownMenuItem.selectable(
        title: title,
        selected: vm.filter == value,
        onTap: () => vm.setFilter(value),
      ),
    if (vm.library.metadata.tags.length > 0) ...[
      const GroupRule(),
      const PullDownMenuTitle(title: Text('Tags')),
      for (final tag in vm.library.metadata.tags.toDart)
        PullDownMenuItem.selectable(
          title: tag.name,
          iconWidget: Icon(
            CupertinoIcons.circle_fill,
            size: 12,
            color: hexColor(tag.color),
          ),
          selected: vm.filter == 'tag' && vm.selectedTag == tag.name,
          onTap: () => vm.setFilter('tag', tag.name),
        ),
    ],
  ];

  List<Widget> notebooksContent() {
    final notebooks = vm.shownNotebooks;
    final notes = vm.shownNotes;
    if (notebooks.isEmpty && notes.isEmpty)
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: vm.query.isEmpty && vm.filter == 'all'
              ? emptyState(
                  CupertinoIcons.book,
                  'Your notebooks appear here.',
                  'New notebook',
                  () => run(() => create(true)),
                )
              : Center(
                  child: Text(
                    vm.query.isNotEmpty
                        ? 'Nothing matches "${vm.query}".'
                        : switch (vm.filter) {
                            'favorites' => 'No pinned notes.',
                            'recent' => 'No recent notes.',
                            'trash' => 'The trash is empty.',
                            _ => 'Nothing has the tag ${vm.selectedTag}.',
                          },
                    style: body.copyWith(color: secondaryLabel),
                  ),
                ),
        ),
      ];
    final places = vm.places;
    return [
      if (notebooks.isNotEmpty)
        ...section(count(notebooks.length, 'notebook'), [
          for (final item in notebooks)
            vm.grid ? notebookCard(item) : notebookRow(item),
        ], 0.62),
      if (notes.isNotEmpty)
        ...section(count(notes.length, 'note'), [
          for (final item in notes)
            vm.grid
                ? noteCard(item, places[native.pathKey(item.path)])
                : noteRow(item, places[native.pathKey(item.path)]),
        ], 0.6),
    ];
  }

  List<Widget> notebookContent(native.Folder item) {
    final metadata = folder.folderMetadata(item.path);
    final notes = vm.ordered(
      item.notes.toDart,
      (note) => note.name,
      (note) => note.modified,
    );
    return [
      // The notebook's cover, title, counts, description and tags.
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                height: 160,
                child: cover(item, titled: false),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(item.name, style: volumeTitle),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notebookSummary(item),
                      style: footnote.copyWith(color: secondaryLabel),
                    ),
                    if (metadata.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(metadata.description, style: body),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(child: tagList(tagNames(metadata.tags))),
                        MergeSemantics(
                          child: Semantics(
                            label: 'Add tag to ${item.name}',
                            button: true,
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(44, 44),
                              onPressed: () =>
                                  run(() => folderAction(item, 'details')),
                              child: const Icon(CupertinoIcons.plus_circle),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      if (notes.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: emptyState(
            CupertinoIcons.pencil_outline,
            'This notebook has no notes yet.',
            'Create note',
            () => run(() => create(false)),
          ),
        )
      else
        ...section(count(notes.length, 'note'), [
          for (final note in notes)
            vm.grid ? noteCard(note, null) : noteRow(note, null),
        ], 0.6),
    ];
  }

  // An empty view holds the action that fills it.
  Widget emptyState(
    IconData icon,
    String message,
    String action,
    VoidCallback onPressed,
  ) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: tertiaryLabel),
        const SizedBox(height: 16),
        Text(message, style: body.copyWith(color: secondaryLabel)),
        const SizedBox(height: 20),
        CupertinoButton.filled(
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.add, size: 20),
              const SizedBox(width: 8),
              Text(action),
            ],
          ),
        ),
      ],
    ),
  );

  Widget toolbar(native.Folder? notebook) => Row(
    children: [
      if (notebook == null) ...[
        Expanded(
          child: SearchField(
            controller: search,
            focusNode: searchFocus,
            placeholder: 'Search notebooks and notes',
            onChanged: vm.setQuery,
          ),
        ),
        menu(
          filterLabel,
          CupertinoIcons.line_horizontal_3_decrease,
          filterMenu,
        ),
      ] else
        const Spacer(),
      menu('Sort', CupertinoIcons.arrow_up_arrow_down, sortMenu),
      const SizedBox(width: 8),
      if (notebook == null &&
          (vm.filter != 'all' ||
              vm.query.isNotEmpty ||
              vm.library.folders.toDart.any(
                (item) => item.path.length > 0 || item.notes.length > 0,
              )))
        Row(children: [
        CupertinoButton.filled(
          onPressed: () => run(() => create(true)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.add, size: 20),
              SizedBox(width: 8),
              Text('New notebook'),
            ],
          ),
        ),
        if (vm.library.folders.toDart.any((item) => item.path.length > 0))
        PullDownButton(
          itemBuilder: (_) {
            final notebooks = vm.library.folders.toDart
                .where((item) => item.path.length > 0)
                .toList();
            notebooks.sort((a, b) => b.modified.compareTo(a.modified));
            final recent = notebooks.firstOrNull;
            return [
              if (recent != null) ...[
                PullDownMenuItem(
                  title: 'New note in ${recent.name}',
                  icon: CupertinoIcons.pencil,
                  onTap: () => run(() => create(false, recent.path)),
                ),
                PullDownMenuItem(
                  title: 'New note in…',
                  icon: CupertinoIcons.folder,
                  onTap: () => run(() async {
                    final selected = await chooseFolder(
                      context,
                      'Choose notebook',
                      notebooks,
                      (item) => item.name,
                    );
                    if (selected != null) await create(false, selected.path);
                  }),
                ),
              ],
            ];
          },
          buttonBuilder: (context, showMenu) => CupertinoButton(
            onPressed: showMenu,
            child: Semantics(
              label: 'Create options',
              button: true,
              child: const Icon(CupertinoIcons.chevron_down),
            ),
          ),
        ),
        ])
      else ...[
        CupertinoButton(
          onPressed: () => run(vm.importPdf),
          child: const Text('Import PDF'),
        ),
        CupertinoButton.filled(
          onPressed: () => run(() => create(false)),
          child: const Text('New note'),
        ),
      ],
    ],
  );

  Widget disconnected() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(CupertinoIcons.book, size: 64),
        const SizedBox(height: 24),
        const Text('Your notes live in a folder on this device.'),
        const SizedBox(height: 24),
        if (folder.reconnect)
          CupertinoButton.filled(
            onPressed: () => run(folder.grantPermission),
            child: const Text('Reconnect folder'),
          ),
        withEnabledState(
          CupertinoButton(
            onPressed: folder.started ? () => run(vm.chooseRoot) : null,
            child: const Text('Choose notes folder'),
          ),
        ),
      ],
    ),
  );

  // A sidebar row in ink. The selected row lies on leaf, in bold, with its
  // icon in the ribbon color.
  Widget sidebarRow({
    required Widget leading,
    required String text,
    required VoidCallback onPressed,
    bool selected = false,
    Widget? trailing,
  }) {
    final color = selected ? accent : label;
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? surface2 : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: HoverTint(
          radius: 8,
          child: CupertinoButton(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: onPressed,
            child: IconTheme.merge(
              data: IconThemeData(color: color, size: 20),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: (selected ? headline : body).copyWith(
                        color: label,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget treeRow({
    required String text,
    required IconData icon,
    required int depth,
    required VoidCallback onPressed,
    bool selected = false,
    IconData? trailing,
  }) => Padding(
    padding: EdgeInsets.only(left: depth * 16.0),
    child: sidebarRow(
      leading: Icon(icon, size: 17),
      text: text,
      selected: selected,
      onPressed: onPressed,
      trailing: trailing == null ? null : Icon(trailing, size: 14),
    ),
  );

  bool treeNoteMatches(native.Note note) {
    final metadata = folder.noteMetadata(note);
    return vm.matches([
      note.name,
      metadata.description,
      LibraryViewModel.tagText(metadata.tags),
    ]);
  }

  List<Widget> notebookBranch(native.Folder item, int depth) {
    final key = native.pathKey(item.path);
    final expanded = expandedNotebooks.contains(key) || vm.query.isNotEmpty;
    final children = vm.library.folders.toDart
        .where((folder) =>
            folder.path.length == item.path.length + 1 &&
            native.pathKey(folder.path).startsWith('$key/'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final notes = item.notes.toDart.where(treeNoteMatches).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final childBranches = [
      for (final child in children) ...notebookBranch(child, depth + 1),
    ];
    final metadata = folder.folderMetadata(item.path);
    if (vm.query.isNotEmpty &&
        !vm.matches([
          item.name,
          metadata.description,
          LibraryViewModel.tagText(metadata.tags),
        ]) &&
        notes.isEmpty &&
        childBranches.isEmpty) {
      return [];
    }
    return [
      treeRow(
        text: item.name,
        icon: CupertinoIcons.book,
        depth: depth,
        selected: vm.notebookPath != null &&
            native.pathKey(vm.notebookPath!) == key,
        trailing: expanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
        onPressed: () {
          setState(() {
            if (expanded) {
              expandedNotebooks.remove(key);
            } else {
              expandedNotebooks.add(key);
            }
          });
          vm.showNotebook(item.path);
        },
      ),
      if (expanded) ...[
        ...childBranches,
        for (final note in notes)
          treeRow(
            text: note.name,
            icon: CupertinoIcons.doc_text,
            depth: depth + 1,
            onPressed: () => run(() => session.open(note.path)),
          ),
      ],
    ];
  }

  Widget sidebar() {
    final tags = vm.library.metadata.tags.toDart;
    final topNotebooks = vm.library.folders.toDart
        .where((item) => item.path.length == 1)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final items = [
      (
        label: 'Library',
        icon: CupertinoIcons.book,
        selected: vm.filter == 'all' && vm.query.isEmpty,
        action: () {
          vm.showNotebook(null);
          vm.setFilter('all');
          search.clear();
          vm.setQuery('');
        },
      ),
      (
        label: 'Recent',
        icon: CupertinoIcons.clock,
        selected: vm.filter == 'recent',
        action: () {
          vm.showNotebook(null);
          search.clear();
          vm.setQuery('');
          vm.setFilter('recent');
        },
      ),
      (
        label: 'Pinned',
        icon: CupertinoIcons.pin,
        selected: vm.filter == 'favorites',
        action: () {
          vm.showNotebook(null);
          search.clear();
          vm.setQuery('');
          vm.setFilter('favorites');
        },
      ),
      (
        label: 'Trash',
        icon: CupertinoIcons.trash,
        selected: vm.filter == 'trash',
        action: () {
          vm.showNotebook(null);
          search.clear();
          vm.setQuery('');
          vm.setFilter('trash');
        },
      ),
    ];
    final notes = vm.library.folders.toDart.expand((item) => item.notes.toDart);
    return SizedBox(
      width: 220,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: surface1,
          border: Border(right: BorderSide(color: separator)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Row(children: [Text('Math Notes', style: title)]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
              for (final item in items) ...[
                sidebarRow(
                  leading: Icon(item.icon),
                  text: item.label,
                  selected: item.selected,
                  trailing: item.label == 'Library'
                      ? Icon(libraryExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right, size: 14)
                      : item.label == 'Trash'
                      ? Icon(trashExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right, size: 14)
                      : null,
                  onPressed: () {
                    item.action();
                    if (item.label == 'Library') {
                      setState(() => libraryExpanded = !libraryExpanded);
                    } else if (item.label == 'Trash') {
                      setState(() => trashExpanded = !trashExpanded);
                    }
                  },
                ),
                if (item.label == 'Library' && libraryExpanded) ...[
                  treeRow(
                    text: 'Untagged',
                    icon: CupertinoIcons.tray,
                    depth: 1,
                    trailing: untaggedExpanded
                        ? CupertinoIcons.chevron_down
                        : CupertinoIcons.chevron_right,
                    onPressed: () => setState(
                      () => untaggedExpanded = !untaggedExpanded,
                    ),
                  ),
                  if (untaggedExpanded)
                    for (final note in notes.where(
                      (note) => folder.noteMetadata(note).tags.length == 0 &&
                          treeNoteMatches(note),
                    ))
                      treeRow(
                        text: note.name,
                        icon: CupertinoIcons.doc_text,
                        depth: 2,
                        onPressed: () => run(() => session.open(note.path)),
                      ),
                  for (final notebook in topNotebooks)
                    ...notebookBranch(notebook, 1),
                ],
                if (item.label == 'Trash' && trashExpanded)
                  for (final note in vm.library.trash.toDart.where(treeNoteMatches))
                    treeRow(
                      text: note.name,
                      icon: CupertinoIcons.doc_text,
                      depth: 1,
                      onPressed: () => vm.setFilter('trash'),
                    ),
              ],
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 4),
                  child: Text(
                    'Tags',
                    style: footnote.copyWith(color: secondaryLabel),
                  ),
                )
              else
                const SizedBox(height: 12),
                      for (final tag in tags)
                        sidebarRow(
                          leading: Icon(
                            CupertinoIcons.circle_fill,
                            size: 10,
                            color: hexColor(tag.color),
                          ),
                          text: tag.name,
                          selected:
                              vm.filter == 'tag' && vm.selectedTag == tag.name,
                          // The tag view lists the notebooks and the notes
                          // that carry the tag; the count counts both.
                          trailing: Text(
                            '${vm.library.folders.toDart.where((item) => tagged(folder.folderMetadata(item.path).tags, tag.name)).length + notes.where((note) => tagged(folder.noteMetadata(note).tags, tag.name)).length}',
                            style: callout.copyWith(color: secondaryLabel),
                          ),
                          onPressed: () {
                            vm.showNotebook(null);
                            search.clear();
                            vm.setQuery('');
                            vm.setFilter('tag', tag.name);
                          },
                        ),
                      sidebarRow(
                        leading: const Icon(CupertinoIcons.add),
                        text: 'New tag',
                        onPressed: () => run(addTag),
                      ),
                    ],
                  ),
                ),
              ),
              sidebarRow(
                leading: const Icon(CupertinoIcons.settings),
                text: 'Settings',
                onPressed: () => run(
                  () => showSettings(
                    context,
                    onChooseFolder: () => run(vm.chooseRoot),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryViewModel>();
    final tasks = context.watch<Activity>().tasks;
    final connected = folder.connected;
    final notebook = vm.notebook;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: notebook == null
            ? null
            // The sidebar's Library row has the visible name too; the
            // label gives the workflows a distinct selector.
            : MergeSemantics(
                child: Semantics(
                  label: 'Back to library',
                  button: true,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => vm.showNotebook(null),
                    child: const ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.chevron_left),
                          Text('Library'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Under a dialog the action waits for the user, not for work,
            // and a turning spinner redraws the blurred screen each frame.
            if (tasks > 0 && ModalRoute.isCurrentOf(context)!)
              const CupertinoActivityIndicator(),
            if (connected && notebook != null)
              actionsButton(
                '${notebook.name} notebook actions',
                () => folderMenu(notebook),
              ),
          ],
        ),
      ),
      // Tab finishes one region before the next: the sidebar, the toolbar,
      // then the content.
      child: SafeArea(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Row(
            children: [
              if (connected) region(1, sidebar()),
              Expanded(
                child: Column(
                  children: [
                    if (vm.confirmation != null)
                      Semantics(
                        role: SemanticsRole.status,
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(vm.confirmation!),
                        ),
                      ),
                    Expanded(
                      child: connected
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (notebook == null) ...[
                                    Text(heading, style: volumeTitle),
                                    const SizedBox(height: 12),
                                  ],
                                  region(2, toolbar(notebook)),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: region(
                                      3,
                                      CustomScrollView(
                                        slivers: notebook == null
                                            ? notebooksContent()
                                            : notebookContent(notebook),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : disconnected(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget region(double order, Widget child) => FocusTraversalOrder(
    order: NumericFocusOrder(order),
    child: FocusTraversalGroup(child: child),
  );
}
