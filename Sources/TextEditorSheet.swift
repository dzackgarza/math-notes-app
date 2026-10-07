import CoreGraphics
import SwiftUI
import UIKit

struct EditorTextRequest: Identifiable, Equatable {
  let id = UUID()
  let point: CGPoint
  let existing: Bool
  let properties: EngineTextProperties
}

struct TextEditorSheet: View {
  let request: EditorTextRequest
  let onSave: (EngineTextProperties) -> Void
  let onCancel: () -> Void

  @State private var content: String
  @State private var width: String
  @State private var rtl: Bool
  @State private var validationMessage: String?

  init(
    request: EditorTextRequest,
    onSave: @escaping (EngineTextProperties) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.request = request
    self.onSave = onSave
    self.onCancel = onCancel
    _content = State(initialValue: request.properties.content)
    _width = State(initialValue: String(request.properties.width))
    _rtl = State(initialValue: request.properties.rtl)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Text") {
          ZStack(alignment: .topLeading) {
            if content.isEmpty {
              Text("Text")
                .foregroundStyle(NativeTheme.graphite)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }
            NoteTextView(text: $content, rtl: rtl)
              .frame(minHeight: 140)
          }
        }

        Section("Text box") {
          TextField("Width (pt)", text: $width)
            .keyboardType(.decimalPad)
            .nativeFieldSurface()
          Text("Use 0 for the full text width.")
            .font(NativeTheme.footnote)
            .foregroundStyle(NativeTheme.graphite)
          if let validationMessage {
            Text(validationMessage)
              .foregroundStyle(.red)
          }
          Toggle("Right to left", isOn: $rtl)
        }
      }
      .scrollContentBackground(.hidden)
      .nativeSheetSurface()
      .navigationTitle(request.existing ? "Edit text" : "Insert text")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            guard let widthValue else {
              validationMessage = "Use a width from 0 to 100000 pt."
              return
            }
            onSave(
              EngineTextProperties(
                content: content,
                width: widthValue,
                rtl: rtl))
          }
        }
      }
    }
  }

  private var widthValue: Double? {
    guard let value = Double(width), value.isFinite, value >= 0, value <= 100_000 else {
      return nil
    }
    return value
  }
}

let noteTextFallbackFontNames = [
  "NotoSansArabic-Regular",
  "NotoSansHebrew-Regular",
  "NotoSansDevanagari-Regular",
  "NotoSansSymbols2-Regular",
]

func noteTextFont(size: CGFloat) -> UIFont {
  let fallback = noteTextFallbackFontNames.map { UIFontDescriptor(name: $0, size: size) }
  let descriptor = UIFontDescriptor(name: "NotoSans-Regular", size: size)
    .addingAttributes([.cascadeList: fallback])
  return UIFont(descriptor: descriptor, size: size)
}

private struct NoteTextView: UIViewRepresentable {
  @Binding var text: String
  let rtl: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator
    view.backgroundColor = .clear
    view.text = text
    view.font = noteTextFont(size: 18)
    view.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
    view.accessibilityLabel = "Text"
    context.coordinator.appliedRTL = rtl
    applyDirection(to: view)
    DispatchQueue.main.async { view.becomeFirstResponder() }
    return view
  }

  func updateUIView(_ view: UITextView, context: Context) {
    let externalTextChanged = view.text != text && view.markedTextRange == nil
    if externalTextChanged { view.text = text }
    view.font = noteTextFont(size: 18)
    if externalTextChanged || context.coordinator.appliedRTL != rtl {
      applyDirection(to: view)
      context.coordinator.appliedRTL = rtl
    }
  }

  private func applyDirection(to view: UITextView) {
    let direction: NSWritingDirection = rtl ? .rightToLeft : .leftToRight
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = direction
    if view.markedTextRange == nil, view.textStorage.length > 0 {
      let selection = view.selectedRange
      view.textStorage.addAttribute(
        .paragraphStyle,
        value: paragraph,
        range: NSRange(location: 0, length: view.textStorage.length))
      view.selectedRange = selection
    }
    view.typingAttributes[.paragraphStyle] = paragraph
    view.textAlignment = rtl ? .right : .left
    view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var appliedRTL: Bool?
    @Binding private var text: String

    init(text: Binding<String>) {
      _text = text
    }

    func textViewDidChange(_ textView: UITextView) {
      text = textView.text
    }
  }
}
