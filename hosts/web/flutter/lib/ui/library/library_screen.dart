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
                  ? 'Remove favorite'
                  : 'Add favorite',
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
    if (await editFolderDetails(context, '${item.name} details', values))
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

  Future<void> create(bool isFolder) async {
    await vm.prepareCreation();
    if (!mounted) return;
    final form = await askCreation(
      context,
      isFolder: isFolder,
      engine: folder.engine!,
      root: folder.root!,
      metadata: vm.library.metadata,
      folders: vm.library.folders.toDart,
      notebook: vm.notebookPath,
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
              Text(name, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }

  Iterable<String> tagNames(JSArray<JSString> tags) =>
      tags.toDart.map((tag) => tag.toDart);

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

  // The whole card or row is one tap target. `onTap` receives its context.
  Widget tappable(
    String label,
    void Function(BuildContext) onTap,
    Widget child,
  ) => Semantics(
    label: label,
    button: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(context),
          child: child,
        ),
      ),
    ),
  );

  Widget cover(native.Folder item, {bool titled = true}) {
    final metadata = folder.folderMetadata(item.path);
    final color = hexColor(metadata.coverColor);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: metadata.coverStyle == 'spine'
            ? Border(
                left: BorderSide(
                  color: Color.lerp(color, const Color(0xFF000000), 0.3)!,
                  width: 10,
                ),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: titled
              ? Text(
                  item.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  String notebookSummary(native.Folder item) => item.notes.length == 0
      ? 'No notes'
      : '${count(item.notes.length, 'note')} · ${modifiedLabel(item.modified)}';

  Widget notebookCard(native.Folder item) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return tappable(
      'Open ${item.name}',
      (_) => vm.showNotebook(item.path),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cover(item)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.notes.length == 0
                      ? 'No notes'
                      : count(item.notes.length, 'note'),
                ),
              ),
              actionsButton(
                '${item.name} notebook actions',
                () => folderMenu(item),
              ),
            ],
          ),
          if (item.notes.length > 0)
            Text(
              modifiedLabel(item.modified),
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          tagList(tagNames(folder.folderMetadata(item.path).tags)),
        ],
      ),
    );
  }

  Widget notebookRow(native.Folder item) => tappable(
    'Open ${item.name}',
    (_) => vm.showNotebook(item.path),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 48, height: 64, child: cover(item, titled: false)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  notebookSummary(item),
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
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
  Widget noteCard(native.Note item, String? place) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return tappable(
      'Open ${item.name}',
      (card) => tapNote(card, item),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumbnail(item),
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              actionsButton('${item.name} actions', () => noteMenu(item)),
            ],
          ),
          Text(
            [?place, modifiedLabel(item.modified)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          tagList(tagNames(folder.noteMetadata(item).tags)),
        ],
      ),
    );
  }

  Widget noteRow(native.Note item, String? place) => tappable(
    'Open ${item.name}',
    (card) => tapNote(card, item),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 48, height: 64, child: thumbnail(item)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  noteTitle(item),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [?place, modifiedLabel(item.modified)].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
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
        child: Text(
          heading,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
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
    const PullDownMenuDivider.large(),
    for (final (value, title)
        in vm.sort == 'name'
            ? const [(true, 'A to Z'), (false, 'Z to A')]
            : const [(false, 'Newest first'), (true, 'Oldest first')])
      PullDownMenuItem.selectable(
        title: title,
        selected: vm.ascending == value,
        onTap: () => vm.setAscending(value),
      ),
    const PullDownMenuDivider.large(),
    for (final (value, title) in const [(true, 'Grid'), (false, 'List')])
      PullDownMenuItem.selectable(
        title: title,
        selected: vm.grid == value,
        onTap: () => vm.setGrid(value),
      ),
  ];

  String get filterLabel => switch (vm.filter) {
    'favorites' => 'Favorites',
    'recent' => 'Recent',
    'trash' => 'Trash',
    'tag' => vm.selectedTag!,
    _ => 'All',
  };

  List<PullDownMenuEntry> filterMenu() => [
    for (final (value, title) in const [
      ('all', 'All'),
      ('recent', 'Recent'),
      ('favorites', 'Favorites'),
      ('trash', 'Trash'),
    ])
      PullDownMenuItem.selectable(
        title: title,
        selected: vm.filter == value,
        onTap: () => vm.setFilter(value),
      ),
    if (vm.library.metadata.tags.length > 0) ...[
      const PullDownMenuDivider.large(),
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

  List<PullDownMenuEntry> settingsMenu() => [
    PullDownMenuItem(title: 'New tag', onTap: () => run(addTag)),
    PullDownMenuItem(
      title: 'Choose notes folder',
      onTap: () => run(vm.chooseRoot),
    ),
  ];

  List<Widget> notebooksContent() {
    final notebooks = vm.shownNotebooks;
    final notes = vm.shownNotes;
    if (notebooks.isEmpty && notes.isEmpty)
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              vm.query.isNotEmpty
                  ? 'Nothing matches "${vm.query}".'
                  : switch (vm.filter) {
                      'favorites' => 'No favorite notes.',
                      'recent' => 'No recent notes.',
                      'trash' => 'The trash is empty.',
                      'tag' => 'Nothing has the tag ${vm.selectedTag}.',
                      _ => 'No notebooks. Tap New Notebook to make one.',
                    },
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
      if (metadata.description.isNotEmpty || metadata.tags.length > 0)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (metadata.description.isNotEmpty) Text(metadata.description),
                const SizedBox(height: 8),
                tagList(tagNames(metadata.tags)),
              ],
            ),
          ),
        ),
      if (notes.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text('No notes. Tap New Note to write the first one.'),
          ),
        )
      else
        ...section(count(notes.length, 'note'), [
          for (final note in notes)
            vm.grid ? noteCard(note, null) : noteRow(note, null),
        ], 0.6),
    ];
  }

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
      if (notebook == null)
        CupertinoButton.filled(
          onPressed: () => run(() => create(true)),
          child: const Text('New Notebook'),
        )
      else ...[
        CupertinoButton(
          onPressed: () => run(vm.importPdf),
          child: const Text('Import PDF'),
        ),
        CupertinoButton.filled(
          onPressed: () => run(() => create(false)),
          child: const Text('New Note'),
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
        CupertinoButton(
          onPressed: folder.engine == null ? null : () => run(vm.chooseRoot),
          child: const Text('Choose notes folder'),
        ),
      ],
    ),
  );

  Widget sidebar() {
    final tags = vm.library.metadata.tags.toDart;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
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
        label: 'Search',
        icon: CupertinoIcons.search,
        selected: vm.filter == 'all' && vm.query.isNotEmpty,
        action: () {
          vm.showNotebook(null);
          vm.setFilter('all');
          searchFocus.requestFocus();
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
        label: 'Favorites',
        icon: CupertinoIcons.star,
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
    return SizedBox(
      width: 210,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoTheme.of(context).barBackgroundColor,
          border: Border(
            right: BorderSide(
              color: CupertinoColors.separator.resolveFrom(context),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Text(
                  'Math Notes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              for (final item in items)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: item.selected
                        ? CupertinoColors.systemFill.resolveFrom(context)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CupertinoButton(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    onPressed: item.action,
                    child: Row(
                      children: [
                        Icon(item.icon, size: 20),
                        const SizedBox(width: 10),
                        Text(item.label),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
                child: Text(
                  'Tags',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final tag in tags)
                        CupertinoButton(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          onPressed: () {
                            vm.showNotebook(null);
                            search.clear();
                            vm.setQuery('');
                            vm.setFilter('tag', tag.name);
                          },
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.circle_fill,
                                size: 9,
                                color: hexColor(tag.color),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(tag.name)),
                              Text(
                                '${vm.library.folders.toDart.expand((item) => item.notes.toDart).where((note) => folder.noteMetadata(note).tags.toDart.any((value) => value.toDart == tag.name)).length}',
                                style: TextStyle(color: secondary),
                              ),
                            ],
                          ),
                        ),
                      CupertinoButton(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: () => run(addTag),
                        child: const Row(
                          children: [
                            Icon(CupertinoIcons.add, size: 18),
                            SizedBox(width: 8),
                            Text('New tag'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PullDownButton(
                itemBuilder: (_) => settingsMenu(),
                buttonBuilder: (context, showMenu) => CupertinoButton(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: showMenu,
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.settings, size: 20),
                      SizedBox(width: 10),
                      Text('Settings'),
                    ],
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
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => vm.showNotebook(null),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.chevron_left),
                    Text('Notebooks'),
                  ],
                ),
              ),
        middle: Text(notebook?.name ?? 'Notebooks'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tasks > 0) const CupertinoActivityIndicator(),
            if (connected && notebook != null)
              actionsButton(
                '${notebook.name} notebook actions',
                () => folderMenu(notebook),
              ),
          ],
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (connected) sidebar(),
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
                                toolbar(notebook),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: CustomScrollView(
                                    slivers: notebook == null
                                        ? notebooksContent()
                                        : notebookContent(notebook),
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
    );
  }
}
