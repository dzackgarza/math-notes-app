import 'package:flutter/cupertino.dart';

import 'ui/theme.dart' show fieldDecoration, placeholderText;

class TagEditingController extends ValueNotifier<List<String>> {
  TagEditingController(super.value);

  final input = TextEditingController();

  List<String> get tags =>
      {...value, if (input.text.trim().isNotEmpty) input.text.trim()}.toList();

  void add() {
    value = tags;
    input.clear();
  }

  void replace(List<String> tags) {
    input.clear();
    value = tags;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}

class TagEditor extends StatelessWidget {
  const TagEditor({super.key, required this.controller});

  final TagEditingController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: controller,
    builder: (context, tags, child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in tags)
              MergeSemantics(
                child: Semantics(
                  label: 'Remove tag $tag',
                  button: true,
                  child: CupertinoButton.tinted(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: () => controller.value = tags
                        .where((value) => value != tag)
                        .toList(),
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: Text(tag)),
                          const SizedBox(width: 8),
                          const Icon(CupertinoIcons.xmark, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                cursorOpacityAnimates: false,
                decoration: fieldDecoration,
                placeholderStyle: placeholderText,
                controller: controller.input,
                placeholder: 'Add a tag…',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => controller.add(),
              ),
            ),
            CupertinoButton(
              onPressed: controller.add,
              child: const Text('Add tag'),
            ),
          ],
        ),
      ],
    ),
  );
}
