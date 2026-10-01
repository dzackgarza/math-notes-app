part of 'editor_screen.dart';

extension _FigurePanel on _EditorScreenState {
  Widget figurePanel() => SizedBox(
    width: 280,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TikZ figure', style: subhead),
          Expanded(
            child: CupertinoTextField(
              cursorOpacityAnimates: false,
              placeholderStyle: placeholderText,
              controller: figureText,
              readOnly: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
          if (!drawing)
            CupertinoButton(
              onPressed: () => figureSource = '',
              child: const Text('Close figure preview'),
            ),
        ],
      ),
    ),
  );
}
