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
          TextEditor(text: $content)
            .frame(minHeight: 140)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        }

        Section("Text box") {
          TextField("Width (pt)", text: $width)
            .keyboardType(.decimalPad)
          Text("Use 0 for the full text width.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("Right to left", isOn: $rtl)
        }
      }
      .navigationTitle(request.existing ? "Edit text" : "Insert text")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            guard let widthValue else { return }
            onSave(
              EngineTextProperties(
                content: content,
                width: widthValue,
                rtl: rtl))
          }
          .disabled(widthValue == nil)
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
