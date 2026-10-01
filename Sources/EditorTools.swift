import InkEngine
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
  case pen
  case marker
  case highlighter
  case eraser
  case lasso

  var id: Self { self }

  var label: String {
    switch self {
    case .pen: "Pen"
    case .marker: "Marker"
    case .highlighter: "Highlighter"
    case .eraser: "Eraser"
    case .lasso: "Lasso"
    }
  }

  var systemImage: String {
    switch self {
    case .pen: "pencil.tip"
    case .marker: "paintbrush"
    case .highlighter: "highlighter"
    case .eraser: "eraser"
    case .lasso: "lasso"
    }
  }
}

@MainActor
struct EditorPenSet {
  let pen: InkToolSettings
  let marker: InkToolSettings
  let highlighter: InkToolSettings

  static let defaults: EditorPenSet = {
    var json: UnsafePointer<UInt8>?
    var size = 0
    guard ink_pens_default(&json, &size) == INK_OK, let json else {
      fatalError("ink_pens_default failed: \(EngineDocument.lastError())")
    }

    var file: UnsafePointer<InkPenFile>?
    guard ink_pens_read(json, size, &file) == INK_OK, let file else {
      fatalError("ink_pens_read failed: \(EngineDocument.lastError())")
    }

    return EditorPenSet(
      pen: file.pointee.pen,
      marker: file.pointee.marker,
      highlighter: file.pointee.highlighter)
  }()
}

struct EditorToolRail: View {
  @Binding var tool: EditorTool
  let undo: () -> Void
  let redo: () -> Void

  var body: some View {
    VStack(spacing: 8) {
      ForEach(EditorTool.allCases) { item in
        railButton(
          label: item.label,
          systemImage: item.systemImage,
          selected: tool == item
        ) {
          tool = item
        }
      }

      Divider()
        .frame(width: 28)

      railButton(label: "Undo", systemImage: "arrow.uturn.backward", action: undo)
      railButton(label: "Redo", systemImage: "arrow.uturn.forward", action: redo)
    }
    .padding(8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
    }
    .padding(.leading, 8)
    .padding(.top, 8)
  }

  @ViewBuilder
  private func railButton(
    label: String,
    systemImage: String,
    selected: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 22))
        .frame(width: 42, height: 42)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(selected ? Color.accentColor : Color.primary)
    .background(
      selected ? Color.accentColor.opacity(0.14) : Color.clear,
      in: RoundedRectangle(cornerRadius: 10))
    .accessibilityLabel(label)
    .accessibilityValue(selected ? "Selected" : "")
  }
}
