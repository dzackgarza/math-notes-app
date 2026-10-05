import CoreGraphics
import SwiftUI

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
  @FocusState private var contentFocused: Bool

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
            TextEditor(text: $content)
              .focused($contentFocused)
              .task { contentFocused = true }
              .frame(minHeight: 140)
              .accessibilityLabel("Text")
              .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
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
