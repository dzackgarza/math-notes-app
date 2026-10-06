import Foundation
import InkEngine
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
  case pen
  case marker
  case highlighter
  case eraser
  case lasso
  case text
  case image
  case space
  case navigate

  var id: Self { self }

  static var toolbarCases: [Self] {
    allCases.filter { $0 != .navigate }
  }

  var label: String {
    switch self {
    case .pen: "Pen"
    case .marker: "Marker"
    case .highlighter: "Highlighter"
    case .eraser: "Eraser"
    case .lasso: "Lasso"
    case .space: "Insert space"
    case .navigate: "Follow links"
    case .text: "Text"
    case .image: "Image"
    }
  }

  var systemImage: String {
    switch self {
    case .pen: "pencil.tip"
    case .marker: "paintbrush"
    case .highlighter: "highlighter"
    case .eraser: "eraser"
    case .lasso: "lasso"
    case .space: "arrow.up.and.down.and.arrow.left.and.right"
    case .navigate: "link"
    case .text: "textformat"
    case .image: "photo"
    }
  }
}

enum EditorEraserMode: String, CaseIterable, Identifiable {
  case stroke = "Stroke"
  case partial = "Partial"
  case ruled = "Ruled"

  var id: Self { self }

  var engineValue: InkEraser {
    switch self {
    case .stroke, .ruled: INK_ERASER_STROKE
    case .partial: INK_ERASER_FREE
    }
  }

  var selectorValue: InkSelector? {
    switch self {
    case .stroke, .partial: nil
    case .ruled: INK_SELECTOR_RULED_ERASE
    }
  }

  var systemImage: String {
    switch self {
    case .stroke: "scribble.variable"
    case .partial: "eraser"
    case .ruled: "ruler"
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

enum EditorSpaceMode: String, CaseIterable, Identifiable {
  case vertical = "Vertical"
  case horizontal = "Horizontal"
  case reflow = "Reflow"

  var id: Self { self }

  var engineValue: InkSelector {
    switch self {
    case .vertical: INK_SELECTOR_SPACE_VERTICAL
    case .horizontal: INK_SELECTOR_SPACE_HORIZONTAL
    case .reflow: INK_SELECTOR_SPACE_RULED
    }
  }

  var systemImage: String {
    switch self {
    case .vertical: "arrow.up.and.down"
    case .horizontal: "arrow.left.and.right"
    case .reflow: "text.word.spacing"
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

// The default rail is 13 targets and 12 equal gaps: 13 * 44 + 12 * 8 = 668 pt.
// That leaves the 8 pt top inset inside a 720 pt canvas without vertical padding.
enum EditorToolRailMetrics {
  static let width: CGFloat = 60
  static let targetSize: CGFloat = 44
  static let gap: CGFloat = 8

  static func contentHeight(groupCounts: [Int]) -> CGFloat {
    let groups = groupCounts.filter { $0 > 0 }
    let targets = groups.reduce(0, +)
    guard targets > 0 else { return 0 }
    return CGFloat(targets) * targetSize + CGFloat(targets - 1) * gap
  }
}

@MainActor
struct EditorToolRail: View {
  @Binding var tool: EditorTool
  @Binding var drawingTool: EditorTool
  @Binding var eraserMode: EditorEraserMode
  @Binding var selectorMode: EditorSelectorMode
  @Binding var spaceMode: EditorSpaceMode
  @Binding var penLibrary: EditorPenLibrary
  let hiddenTools: Set<String>
  @State private var showingEraserModes = false
  @State private var showingSelectorModes = false
  @State private var showingSpaceModes = false
  @State private var editingPen: EditorTool?
  @State private var showingColors = false
  let undo: () -> Bool
  let redo: () -> Bool
  let insertText: () -> Void
  let insertImage: () -> Void
  let drawing: Bool
  let selectionActive: Bool
  let clippingsOpen: Bool
  let toggleDrawing: () -> Void
  let showClippings: () -> Void
  let recolorSelection: (UInt32) -> Void
  let onPensChanged: (EditorPenLibrary) -> Void

  var body: some View {
    ViewThatFits(in: .vertical) {
      railContents
      ScrollView(.vertical, showsIndicators: false) {
        railContents
      }
    }
    .frame(width: EditorToolRailMetrics.width)
    .foregroundStyle(NativeTheme.ink)
    .background(NativeTheme.leaf, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(NativeTheme.separator, lineWidth: 1)
    }
    .shadow(color: NativeTheme.ink.opacity(0.18), radius: 9, y: 3)
    .padding(.leading, 8)
    .padding(.top, 8)
    .popover(item: $editingPen, arrowEdge: .leading) { item in
      PenEditorPopover(
        tool: item,
        library: $penLibrary,
        onPersist: onPensChanged)
        .presentationCompactAdaptation(.popover)
    }
    .onChange(of: tool) { _, next in
      if [.pen, .marker, .highlighter].contains(next) {
        drawingTool = next
      }
    }
  }

  private var railContents: some View {
    VStack(spacing: 0) {
      if !visibleWritingTools.isEmpty {
        VStack(spacing: EditorToolRailMetrics.gap) {
          ForEach(visibleWritingTools) { toolControl($0) }
        }
        railSeparator
      }

      VStack(spacing: EditorToolRailMetrics.gap) {
        ForEach(visibleInserterTools) { toolControl($0) }
        if !hiddenTools.contains("drawing") {
          railButton(
            label: drawing ? "Complete drawing" : "Drawing mode",
            systemImage: "scribble.variable",
            selected: drawing,
            action: toggleDrawing)
        }
        railButton(
          label: "Clippings",
          systemImage: "tray",
          selected: clippingsOpen,
          action: showClippings)
      }

      railSeparator

      VStack(spacing: EditorToolRailMetrics.gap) {
        UndoDialButton(undo: undo, redo: redo)
          .disabled(drawing)
        railButton(label: "Redo", systemImage: "arrow.uturn.forward") {
          _ = redo()
        }
        .disabled(drawing)
      }

      railSeparator
      colorButton
    }
  }

  private var railSeparator: some View {
    Divider()
      .overlay(NativeTheme.separator)
      .frame(width: 28, height: EditorToolRailMetrics.gap)
  }

  private var visibleWritingTools: [EditorTool] {
    [.pen, .marker, .highlighter, .eraser, .lasso]
      .filter { !hiddenTools.contains($0.rawValue) }
  }

  private var visibleInserterTools: [EditorTool] {
    [.text, .image, .space]
      .filter { !hiddenTools.contains($0.rawValue) }
  }

  @ViewBuilder
  private func toolControl(_ item: EditorTool) -> some View {
    if item == .eraser {
      eraserButton
    } else if item == .lasso {
      selectorButton
    } else if item == .space {
      spaceButton
        .disabled(drawing)
    } else if item == .text {
      railButton(
        label: item.label,
        systemImage: item.systemImage,
        selected: tool == item
      ) {
        tool = .text
        insertText()
      }
    } else if item == .image {
      railButton(
        label: item.label,
        systemImage: item.systemImage,
        selected: false,
        action: insertImage)
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

  private var colorButton: some View {
    let rgb = penLibrary.settings(for: drawingTool).rgb
    return Button {
      showingColors = true
    } label: {
      Circle()
        .fill(
          Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1))
        .frame(width: 28, height: 28)
        .overlay {
          Circle()
            .stroke(NativeTheme.ink, lineWidth: 2)
        }
        .frame(
          width: EditorToolRailMetrics.targetSize,
          height: EditorToolRailMetrics.targetSize)
    }
    .buttonStyle(.plain)
    .hoverEffect(.highlight)
    .accessibilityLabel(String(format: "Colors #%06x", rgb & 0xFFFFFF))
    .popover(isPresented: $showingColors, arrowEdge: .leading) {
      ColorPalettePopover(
        tool: $tool,
        drawingTool: $drawingTool,
        library: $penLibrary,
        selectionActive: selectionActive,
        onRecolorSelection: recolorSelection,
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
          } label: {
            VStack(spacing: 8) {
              Image(systemName: mode.systemImage)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(
                  eraserMode == mode ? NativeTheme.selectedFill : Color.clear,
                  in: RoundedRectangle(cornerRadius: 10))
              Text(mode.rawValue)
                .font(NativeTheme.footnote)
            }
            .frame(minWidth: 64, minHeight: 72)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(eraserMode == mode ? NativeTheme.ribbon : NativeTheme.ink)
          .accessibilityAddTraits(eraserMode == mode ? .isSelected : [])
        }
      }
      .padding(16)
      .nativePopoverSurface()
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
          } label: {
            VStack(spacing: 8) {
              Image(systemName: mode.systemImage)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(
                  selectorMode == mode ? NativeTheme.selectedFill : Color.clear,
                  in: RoundedRectangle(cornerRadius: 10))
              Text(mode.rawValue)
                .font(NativeTheme.footnote)
            }
            .frame(minWidth: 64, minHeight: 72)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(selectorMode == mode ? NativeTheme.ribbon : NativeTheme.ink)
          .accessibilityAddTraits(selectorMode == mode ? .isSelected : [])
        }
      }
      .padding(16)
      .nativePopoverSurface()
      .presentationCompactAdaptation(.popover)
    }
  }

  private var spaceButton: some View {
    railButton(
      label: "Insert Space, \(spaceMode.rawValue)",
      systemImage: EditorTool.space.systemImage,
      selected: tool == .space
    ) {
      if tool == .space {
        showingSpaceModes = true
      } else {
        tool = .space
      }
    }
    .popover(isPresented: $showingSpaceModes, arrowEdge: .leading) {
      HStack(spacing: 12) {
        ForEach(EditorSpaceMode.allCases) { mode in
          Button {
            spaceMode = mode
            tool = .space
          } label: {
            VStack(spacing: 8) {
              Image(systemName: mode.systemImage)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(
                  spaceMode == mode ? NativeTheme.selectedFill : Color.clear,
                  in: RoundedRectangle(cornerRadius: 10))
              Text(mode.rawValue)
                .font(NativeTheme.footnote)
            }
            .frame(minWidth: 64, minHeight: 72)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(spaceMode == mode ? NativeTheme.ribbon : NativeTheme.ink)
          .accessibilityAddTraits(spaceMode == mode ? .isSelected : [])
        }
      }
      .padding(16)
      .nativePopoverSurface()
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
        .frame(
          width: EditorToolRailMetrics.targetSize,
          height: EditorToolRailMetrics.targetSize)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .hoverEffect(.highlight)
    .foregroundStyle(selected ? NativeTheme.ribbon : NativeTheme.ink)
    .background(
      selected ? NativeTheme.selectedFill : Color.clear,
      in: RoundedRectangle(cornerRadius: 10))
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
