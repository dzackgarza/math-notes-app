import Foundation
import InkEngine
import SwiftUI
import UIKit

@MainActor
struct PenEditorPopover: View {
  let tool: EditorTool
  @Binding var library: EditorPenLibrary
  let onPersist: (EditorPenLibrary) -> Void

  @State private var rgb: UInt32
  @State private var size: Double
  @State private var opacity: Double
  @State private var hex: String
  @State private var saved: [InkToolSettings]

  private let brush: UInt32

  init(
    tool: EditorTool,
    library: Binding<EditorPenLibrary>,
    onPersist: @escaping (EditorPenLibrary) -> Void
  ) {
    self.tool = tool
    _library = library
    self.onPersist = onPersist

    let settings = library.wrappedValue.settings(for: tool)
    brush = settings.brush
    _rgb = State(initialValue: settings.rgb)
    _size = State(initialValue: Double(settings.size))
    _opacity = State(initialValue: Double(settings.opacity))
    _hex = State(initialValue: Self.hex(settings.rgb))
    _saved = State(initialValue: library.wrappedValue.saved)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(tool.label)
        .font(NativeTheme.headline)

      PenPreview(settings: settings)
        .frame(width: 288, height: 64)
        .background(NativeTheme.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(NativeTheme.separator, lineWidth: 1)
        }

      Text("Color")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)

      HStack(spacing: 8) {
        ForEach(Array(library.palette.enumerated()), id: \.offset) { _, color in
          Button {
            setColor(color)
          } label: {
            Circle()
              .fill(swiftUIColor(color))
              .frame(width: 28, height: 28)
              .overlay {
                Circle()
                  .stroke(
                    rgb == color ? NativeTheme.ribbon : NativeTheme.separator,
                    lineWidth: rgb == color ? 3 : 1)
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Color \(Self.hex(color))")
          .accessibilityValue(rgb == color ? "Selected" : "")
        }
      }

      TextField("#RRGGBB", text: $hex)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .font(.system(.body, design: .monospaced))
        .nativeFieldSurface()
        .onSubmit(applyHex)

      Text("Size")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)

      HStack(spacing: 6) {
        ForEach(sizePresets, id: \.self) { value in
          Button(formatSize(value)) {
            size = value
          }
          .buttonStyle(.bordered)
          .tint(abs(size - value) < 0.05 ? NativeTheme.ribbon : NativeTheme.graphite)
        }
      }

      HStack {
        Slider(value: $size, in: 0.2...20)
          .accessibilityLabel("Size")
        Text("\(size, specifier: "%.1f") pt")
          .monospacedDigit()
          .frame(width: 58, alignment: .trailing)
      }

      Text("Opacity")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)

      HStack {
        Slider(value: $opacity, in: 0.1...1, step: 0.1)
          .accessibilityLabel("Opacity")
        Text("\(Int((opacity * 100).rounded()))%")
          .monospacedDigit()
          .frame(width: 48, alignment: .trailing)
      }

      let compatibleSaved = saved.filter { $0.brush == brush }
      if !compatibleSaved.isEmpty {
        Text("Saved Pens")
          .font(NativeTheme.footnote)
          .foregroundStyle(NativeTheme.graphite)

        HStack(spacing: 8) {
          ForEach(Array(compatibleSaved.enumerated()), id: \.offset) { _, preset in
            Button {
              apply(preset)
            } label: {
              VStack(spacing: 4) {
                Circle()
                  .fill(swiftUIColor(preset.rgb))
                  .frame(width: 26, height: 26)
                Text("\(Double(preset.size), specifier: "%.1f")")
                  .font(NativeTheme.footnote)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              "Saved \(tool.label), \(Self.hex(preset.rgb)), \(preset.size) pt")
          }
        }
      }

      Button {
        saved.append(settings)
      } label: {
        Label("Save Pen", systemImage: "bookmark.badge.plus")
      }
      .buttonStyle(.bordered)
    }
    .padding(16)
    .frame(width: 340)
    .nativePopoverSurface()
    .onDisappear(perform: commit)
  }

  private var settings: InkToolSettings {
    var value = InkToolSettings()
    value.brush = brush
    value.rgb = rgb
    value.size = Float(size)
    value.opacity = Float(opacity)
    return value
  }

  private var sizePresets: [Double] {
    switch tool {
    case .highlighter: [4.8, 7.2, 9.6, 14.4, 19.2]
    case .marker: [1.2, 1.8, 2.4, 3.6, 4.8]
    default: [0.6, 1.2, 1.8, 2.4, 3.6]
    }
  }

  private func commit() {
    applyHex()
    var next = library
    next.setSettings(settings, for: tool)
    next.saved = saved
    library = next
    onPersist(next)
  }

  private func apply(_ preset: InkToolSettings) {
    rgb = preset.rgb
    size = Double(preset.size)
    opacity = Double(preset.opacity)
    hex = Self.hex(preset.rgb)
  }

  private func setColor(_ color: UInt32) {
    rgb = color
    hex = Self.hex(color)
  }

  private func applyHex() {
    let text = hex
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard text.count == 6, let value = UInt32(text, radix: 16) else {
      hex = Self.hex(rgb)
      return
    }
    setColor(value)
  }

  private func formatSize(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
  }

  private func swiftUIColor(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }

  private static func hex(_ value: UInt32) -> String {
    String(format: "#%06X", value & 0xFFFFFF)
  }
}

@MainActor
private struct PenPreview: View {
  let settings: InkToolSettings

  @State private var image: UIImage?

  private var key: String {
    "\(settings.brush)-\(settings.rgb)-\(settings.size)-\(settings.opacity)"
  }

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        ProgressView()
      }
    }
    .task(id: key) {
      if let data = try? EditorPenLibrary.previewPNG(
        settings, width: 576, height: 128, scale: 3) {
        image = UIImage(data: data)
      } else {
        image = nil
      }
    }
  }
}
