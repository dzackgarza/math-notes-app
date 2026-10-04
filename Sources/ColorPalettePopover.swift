import Foundation
import InkEngine
import SwiftUI
import UIKit

@MainActor
struct ColorPalettePopover: View {
  @Binding var tool: EditorTool
  @Binding var drawingTool: EditorTool
  @Binding var library: EditorPenLibrary
  let selectionActive: Bool
  let onRecolorSelection: (UInt32) -> Void
  let onPersist: (EditorPenLibrary) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var showingPaletteEditor = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Colors")
        .font(NativeTheme.headline)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 44), spacing: 4)],
        spacing: 4
      ) {
        ForEach(Array(library.palette.enumerated()), id: \.offset) { index, rgb in
          let selected = rgb == currentSettings.rgb
          if !selectionActive && selected {
            ColorPicker(
              "",
              selection: currentSwatchBinding(index: index),
              supportsOpacity: false)
              .labelsHidden()
              .frame(width: 44, height: 44)
              .accessibilityLabel("Color \(hex(rgb))")
              .accessibilityAddTraits(.isSelected)
          } else {
            Button {
              chooseColor(rgb)
            } label: {
              swatch(rgb, selected: selected)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Color \(hex(rgb))")
            .accessibilityAddTraits(selected ? .isSelected : [])
          }
        }

        Button {
          showingPaletteEditor = true
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit colors")
      }

      if !library.saved.isEmpty {
        Text("Saved pens")
          .font(NativeTheme.footnote)
          .foregroundStyle(NativeTheme.graphite)

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 44), spacing: 4)],
          spacing: 4
        ) {
          ForEach(Array(library.saved.enumerated()), id: \.offset) { index, preset in
            let presetTool = library.drawingTool(for: preset)
            Button {
              applySaved(preset)
            } label: {
              Image(systemName: presetTool.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(color(preset.rgb))
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              "Saved pen \(formatSize(preset.size)) pt \(hex(preset.rgb))")
            .contextMenu {
              Button("Remove saved pen", systemImage: "trash", role: .destructive) {
                removeSaved(index)
              }
            }
          }
        }
      }
    }
    .padding(16)
    .frame(width: 300)
    .nativePopoverSurface()
    .popover(isPresented: $showingPaletteEditor, arrowEdge: .leading) {
      PaletteEditorPopover(
        library: $library,
        initialRGB: currentSettings.rgb,
        onPersist: onPersist)
        .presentationCompactAdaptation(.popover)
    }
  }

  private var currentSettings: InkToolSettings {
    library.settings(for: drawingTool)
  }

  private func currentSwatchBinding(index: Int) -> Binding<Color> {
    Binding(
      get: {
        guard library.palette.indices.contains(index) else {
          return color(currentSettings.rgb)
        }
        return color(library.palette[index])
      },
      set: { value in
        guard library.palette.indices.contains(index) else { return }
        let rgb = rgbValue(value, fallback: library.palette[index])
        var next = library
        next.palette[index] = rgb
        next.setColor(rgb, for: drawingTool)
        library = next
        tool = drawingTool
        onPersist(next)
      })
  }

  private func chooseColor(_ rgb: UInt32) {
    if selectionActive {
      onRecolorSelection(rgb)
      dismiss()
      return
    }
    var next = library
    next.setColor(rgb, for: drawingTool)
    library = next
    tool = drawingTool
    onPersist(next)
    dismiss()
  }

  private func applySaved(_ preset: InkToolSettings) {
    let target = library.drawingTool(for: preset)
    var next = library
    next.setSettings(preset, for: target)
    library = next
    drawingTool = target
    tool = target
    onPersist(next)
    dismiss()
  }

  private func removeSaved(_ index: Int) {
    guard library.saved.indices.contains(index) else { return }
    var next = library
    next.saved.remove(at: index)
    library = next
    onPersist(next)
  }

  private func swatch(_ rgb: UInt32, selected: Bool) -> some View {
    Circle()
      .fill(color(rgb))
      .frame(width: 30, height: 30)
      .overlay {
        Circle()
          .stroke(
            selected ? NativeTheme.ribbon : NativeTheme.separator,
            lineWidth: selected ? 3 : 1)
      }
  }
}

@MainActor
private struct PaletteEditorPopover: View {
  @Binding var library: EditorPenLibrary
  let onPersist: (EditorPenLibrary) -> Void

  @State private var newColor: Color

  init(
    library: Binding<EditorPenLibrary>,
    initialRGB: UInt32,
    onPersist: @escaping (EditorPenLibrary) -> Void
  ) {
    _library = library
    self.onPersist = onPersist
    _newColor = State(initialValue: color(initialRGB))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Colors")
        .font(NativeTheme.headline)

      if !library.palette.isEmpty {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 44), spacing: 4)],
          spacing: 4
        ) {
          ForEach(Array(library.palette.enumerated()), id: \.offset) { index, rgb in
            Button {
              removeColor(index)
            } label: {
              ZStack {
                Circle()
                  .fill(color(rgb))
                  .frame(width: 30, height: 30)
                Image(systemName: "xmark")
                  .font(.system(size: 12, weight: .bold))
                  .foregroundStyle(.white)
              }
              .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove color \(hex(rgb))")
          }
        }
      }

      ColorPicker("New color", selection: $newColor, supportsOpacity: false)

      Button("Add color", systemImage: "plus") {
        var next = library
        next.palette.append(rgbValue(newColor, fallback: 0x1A1A1A))
        library = next
        onPersist(next)
      }
      .buttonStyle(.bordered)
    }
    .padding(16)
    .frame(width: 280)
    .nativePopoverSurface()
  }

  private func removeColor(_ index: Int) {
    guard library.palette.indices.contains(index) else { return }
    var next = library
    next.palette.remove(at: index)
    library = next
    onPersist(next)
  }
}

private func color(_ rgb: UInt32) -> Color {
  Color(
    .sRGB,
    red: Double((rgb >> 16) & 0xFF) / 255,
    green: Double((rgb >> 8) & 0xFF) / 255,
    blue: Double(rgb & 0xFF) / 255,
    opacity: 1)
}

private func rgbValue(_ value: Color, fallback: UInt32) -> UInt32 {
  var red: CGFloat = 0
  var green: CGFloat = 0
  var blue: CGFloat = 0
  var alpha: CGFloat = 0
  guard UIColor(value).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
    return fallback
  }

  func channel(_ value: CGFloat) -> UInt32 {
    UInt32((min(max(value, 0), 1) * 255).rounded())
  }
  return (channel(red) << 16) | (channel(green) << 8) | channel(blue)
}

private func hex(_ rgb: UInt32) -> String {
  String(format: "#%06x", rgb & 0xFFFFFF)
}

private func formatSize(_ size: Float) -> String {
  let value = Double(size)
  return value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
}
