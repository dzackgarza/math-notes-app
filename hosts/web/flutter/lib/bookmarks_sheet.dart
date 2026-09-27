import 'dart:js_interop';

import 'package:flutter/cupertino.dart';

import 'host.dart' as native;

Future<native.NavigationMark?> chooseDestination(
  BuildContext context,
  native.Document document,
) {
  final marks = document
      .navigation()
      .toDart
      .where((m) => m.href.isEmpty)
      .toList();
  marks.sort((a, b) {
    final page = a.page.compareTo(b.page);
    return page == 0 ? a.y.compareTo(b.y) : page;
  });
  return showCupertinoModalPopup<native.NavigationMark>(
    context: context,
    builder: (context) => CupertinoPopupSurface(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Pages and bookmarks'),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: marks.length,
                  itemBuilder: (context, index) {
                    final mark = marks[index];
                    return CupertinoListTile(
                      title: Text('Page ${mark.page + 1}'),
                      leading: Icon(
                        mark.id.isEmpty
                            ? CupertinoIcons.doc
                            : CupertinoIcons.bookmark,
                      ),
                      subtitle: mark.id.isEmpty
                          ? null
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Image.memory(
                                document.bookmarkPng(mark.id, 720).toDart,
                                height: 48,
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                              ),
                            ),
                      onTap: () => Navigator.pop(context, mark),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
