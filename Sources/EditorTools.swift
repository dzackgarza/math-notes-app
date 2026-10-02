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

enum EditorEraserMode: String, CaseIterable, Identifiable {
  case stroke = "Stroke"
  case partial = "Partial"

  var id: Self { self }

  var engineValue: InkEraser {
    switch self {
    case .stroke: INK_ERASER_STROKE
    case .partial: INK_ERASER_FREE
    }
  }

  var systemImage: String {
    switch self {
    case .stroke: "scribble.variable"
    case .partial: "eraser"
    }
  }
}

enum EditorSelectorMode: String, CaseIterable, Identifiable {
  case freehand = "Freehand"
  case rectangle = "Rectangle"
  case oval = "Oval"
  case ruled = "Ruled"

  var id: Self { self }

  var engineValue: InkSelector {
    switch self {
    case .freehand: INK_SELECTOR_LASSO
    case .rectangle: INK_SELECTOR_RECT
    case .oval: INK_SELECTOR_OVAL
    case .ruled: INK_SELECTOR_RULED
    }
  }

  var systemImage: String {
    switch self {
    case .freehand: "lasso"
    case .rectangle: "rectangle.dashed"
    case .oval: "circle.dashed"
    case .ruled: "ruler"
    }
  }
}

struct EditorPenSet: Equatable {
  let pen: InkToolSettings
  let marker: InkToolSettings
  let highlighter: InkToolSettings

  static func == (left: EditorPenSet, right: EditorPenSet) -> Bool {
    same(left.pen, right.pen) &&
      same(left.marker, right.marker) &&
      same(left.highlighter, right.highlighter)
  }

  private static func same(_ left: InkToolSettings, _ right: InkToolSettings) -> Bool {
    left.brush == right.brush &&
      left.rgb == right.rgb &&
      left.size == right.size &&
      left.opacity == right.opacity
  }

  @MainActor static let defaults: EditorPenSet = {
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

@MainActor
struct EditorToolRail: View {
  @Binding var tool: EditorTool
  @Binding var eraserMode: EditorEraserMode
  @Binding var selectorMode: EditorSelectorMode
  @Binding var penLibrary: EditorPenLibrary
  @State private var showingEraserModes = false
  @State private var showingSelectorModes = false
  @State private var editingPen: EditorTool?
  let undo: () -> Void
  let redo: () -> Void
  let onPensChanged: (EditorPenLibrary) -> Void

  var body: some View {
    VStack(spacing: 8) {
      ForEach(EditorTool.allCases) { item in
        if item == .eraser {
          eraserButton
        } else if item == .lasso {
          selectorButton
        } else {
          railButton(
            label: item.label,
            systemImage: item.systemImage,
            selected: tool == item
          ) {
            if tool == item {
              editingPen = item
            } else {
              tool = item
            }
          }
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
    .popover(item: $editingPen, arrowEdge: .leading) { item in
      PenEditorPopover(
        tool: item,
        library: $penLibrary,
        onPersist: onPensChanged)
        .presentationCompactAdaptation(.popover)
    }
  }

  private var eraserButton: some View {
    railButton(
      label: "Eraser, \(eraserMode.rawValue)",
      systemImage: EditorTool.eraser.systemImage,
      selected: tool == .eraser
    ) {
      if tool == .eraser {
        showingEraserModes = true
      } else {
        tool = .eraser
      }
    }
    .popover(isPresented: $showingEraserModes, arrowEdge: .leading) {
      HStack(spacing: 12) {
        ForEach(EditorEraserMode.allCases) { mode in
          Button {
            eraserMode = mode
            tool = .eraser
            showingEraserModes = false
          } label: {
            VStack(spacing: 8) {
              Image(systemName: mode.systemImage)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(
                  eraserMode == mode ? Color.accentColor.opacity(0.14) : Color.clear,
                  in: RoundedRectangle(cornerRadius: 10))
              Text(mode.rawValue)
                .font(.caption)
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(eraserMode == mode ? Color.accentColor : Color.primary)
          .accessibilityValue(eraserMode == mode ? "Selected" : "")
        }
      }
      .padding(16)
      .presentationCompactAdaptation(.popover)
    }
  }

  private var selectorButton: some View {
    railButton(
      label: "Lasso, \(selectorMode.rawValue)",
      systemImage: EditorTool.lasso.systemImage,
      selected: tool == .lasso
    ) {
      if tool == .lasso {
        showingSelectorModes = true
      } else {
        tool = .lasso
      }
    }
    .popover(isPresented: $showingSelectorModes, arrowEdge: .leading) {
      HStack(spacing: 12) {
        ForEach(EditorSelectorMode.allCases) { mode in
          Button {
            selectorMode = mode
            tool = .lasso
            showingSelectorModes = false
          } label: {
            VStack(spacing: 8) {
              Image(systemName: mode.systemImage)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(
                  selectorMode == mode ? Color.accentColor.opacity(0.14) : Color.clear,
                  in: RoundedRectangle(cornerRadius: 10))
              Text(mode.rawValue)
                .font(.caption)
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(selectorMode == mode ? Color.accentColor : Color.primary)
          .accessibilityValue(selectorMode == mode ? "Selected" : "")
        }
      }
      .padding(16)
      .presentationCompactAdaptation(.popover)
    }
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
