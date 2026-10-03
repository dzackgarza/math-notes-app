import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../data/open_notes.dart';
import '../data/app_preferences.dart';
import 'editor/tools_view_model.dart';
import 'modal.dart';
import 'theme.dart';

// The Settings sheet (docs/specs/tablet-ui.md, Editor): the app preferences
// as a grouped form. The library adds its notes folder, and the editor adds
// its follow-links mode.
Future<void> showSettings(
  BuildContext context, {
  Future<void> Function()? onChooseFolder,
  bool Function()? followsLinks,
  ValueChanged<bool>? onFollowLinks,
}) {
  final tools = context.read<ToolsViewModel>();
  final session = context.read<OpenNotes>();
  final preferences = context.read<AppPreferences>();
  return showModalDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        Widget toggle(String title, bool value, ValueChanged<bool> onChanged) =>
            MergeSemantics(
              child: CupertinoListTile(
                title: Text(title, style: body),
                trailing: CupertinoSwitch(
                  value: value,
                  onChanged: (next) => update(() => onChanged(next)),
                ),
              ),
            );
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 720,
                ),
                child: Semantics(
                  role: SemanticsRole.dialog,
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: 'Settings',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface2,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: modalShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text('Settings', style: headline),
                                ),
                              ),
                              CupertinoButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Done', style: subhead),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              children: [
                                CupertinoListSection.insetGrouped(
                                  backgroundColor: surface2,
                                  header: Text(
                                    'Appearance',
                                    style: footnote.copyWith(color: secondaryLabel),
                                  ),
                                  children: [
                                    CupertinoListTile(
                                      title: Text('Theme', style: body),
                                      trailing: SizedBox(
                                        width: 190,
                                        child: CupertinoSlidingSegmentedControl<bool>(
                                          groupValue: preferences.darkAppearance,
                                          children: const {
                                            false: Text('Light'),
                                            true: Text('Dark'),
                                          },
                                          onValueChanged: (dark) => update(
                                            () => preferences.darkAppearance = dark!,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                CupertinoListSection.insetGrouped(
                                  backgroundColor: surface2,
                                  children: [
                                    toggle(
                                      'Draw with finger',
                                      tools.fingerDraws,
                                      (value) => tools.fingerDraws = value,
                                    ),
                                    if (followsLinks != null)
                                      toggle(
                                        'Follow links',
                                        followsLinks(),
                                        onFollowLinks!,
                                      ),
                                    toggle(
                                      'Show tab strip',
                                      !session.tabsHidden,
                                      (value) => session.hideTabs(!value),
                                    ),
                                  ],
                                ),
                                CupertinoListSection.insetGrouped(
                                  backgroundColor: surface2,
                                  header: Text(
                                    'History and startup',
                                    style: footnote.copyWith(color: secondaryLabel),
                                  ),
                                  children: [
                                    CupertinoListTile(
                                      title: Text('Undo dial steps', style: body),
                                      trailing: SizedBox(
                                        width: 220,
                                        child: CupertinoSlidingSegmentedControl<int>(
                                          groupValue: preferences.undoDialSteps,
                                          children: {
                                            for (final count in AppPreferences.dialChoices)
                                              count: Text('$count'),
                                          },
                                          onValueChanged: (count) => update(
                                            () => preferences.undoDialSteps = count!,
                                          ),
                                        ),
                                      ),
                                    ),
                                    toggle(
                                      'Open last note on launch',
                                      preferences.reopenLastNote,
                                      (value) => preferences.reopenLastNote = value,
                                    ),
                                  ],
                                ),
                                CupertinoListSection.insetGrouped(
                                  backgroundColor: surface2,
                                  header: Text(
                                    'Toolbar',
                                    style: footnote.copyWith(
                                      color: secondaryLabel,
                                    ),
                                  ),
                                  children: [
                                    for (final (kind, title, _) in toolKinds)
                                      toggle(
                                        title,
                                        !tools.hiddenTools.contains(kind),
                                        (shown) =>
                                            tools.setToolVisible(kind, shown),
                                      ),
                                  ],
                                ),
                                if (onChooseFolder != null)
                                  CupertinoListSection.insetGrouped(
                                    backgroundColor: surface2,
                                    header: Text(
                                      'Notes folder',
                                      style: footnote.copyWith(
                                        color: secondaryLabel,
                                      ),
                                    ),
                                    children: [
                                      Semantics(
                                        button: true,
                                        child: CupertinoListTile(
                                          title: Text(
                                            'Choose notes folder',
                                            style: body,
                                          ),
                                          onTap: () {
                                            Navigator.pop(context);
                                            unawaited(onChooseFolder());
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
