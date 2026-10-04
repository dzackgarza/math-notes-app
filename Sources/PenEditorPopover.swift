import Foundation
import InkEngine
import SwiftUI
import UIKit

@MainActor
struct PenEditorPopover: View {
  let tool: EditorTool
  @Binding var library: EditorPenLibrary
  let onPersist: (EditorPenLibrary) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var size: Double
  @State private var opacity: Double
  @State private var saved: [InkToolSettings]
  @State private var advanced = false

  private let brush: UInt32
  private let rgb: UInt32

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
    rgb = settings.rgb
    _size = State(initialValue: Double(settings.size))
    _opacity = State(initialValue: Double(settings.opacity))
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

      if PenEditorLayout.showsSize(for: tool, advanced: advanced) {
        Text("Size")
          .font(NativeTheme.footnote)
          .foregroundStyle(NativeTheme.graphite)

        HStack(spacing: 7) {
          ForEach(Array(PenEditorLayout.sizePresets(for: tool).enumerated()), id: \.offset) { index, value in
            Button {
              size = value
            } label: {
              VStack(spacing: 4) {
                Circle()
                  .fill(penColor)
                  .frame(width: 3 + CGFloat(4 * index), height: 3 + CGFloat(4 * index))
                Text("\(formatSize(value)) pt")
                  .font(NativeTheme.footnote)
                  .foregroundStyle(NativeTheme.ink)
              }
              .frame(width: 56, height: 56)
              .background(NativeTheme.paper, in: RoundedRectangle(cornerRadius: 8))
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .stroke(
                    abs(size - value) < 0.05 ? NativeTheme.ribbon : Color.clear,
                    lineWidth: 2)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(formatSize(value)) pt")
            .accessibilityValue(abs(size - value) < 0.05 ? "Selected" : "")
          }
        }

        HStack {
          Slider(value: $size, in: 0.2...20, step: 0.2)
            .accessibilityLabel("Size")
          Text("\(size, specifier: "%.1f") pt")
            .monospacedDigit()
            .frame(width: 58, alignment: .trailing)
        }
      }

      if PenEditorLayout.showsOpacity(for: tool, advanced: advanced) {
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
      }

      if tool != .highlighter {
        Picker("Pen settings section", selection: $advanced) {
          Label("Settings", systemImage: "pencil")
            .tag(false)
          Label("Advanced", systemImage: "slider.horizontal.3")
            .tag(true)
        }
        .pickerStyle(.segmented)
      }

      Button {
        saved.append(settings)
        dismiss()
      } label: {
        Label("Save pen", systemImage: "bookmark.badge.plus")
      }
      .buttonStyle(.bordered)
    }
    .padding(16)
    .frame(width: 340)
    .nativePopoverSurface()
    .onDisappear(perform: commit)
  }

  private var penColor: Color {
    Color(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255)
  }

  private var settings: InkToolSettings {
    var value = InkToolSettings()
    value.brush = brush
    value.rgb = rgb
    value.size = Float(size)
    value.opacity = Float(opacity)
    return value
  }

  private func commit() {
    var next = library
    next.setSettings(settings, for: tool)
    next.saved = saved
    library = next
    onPersist(next)
  }

  private func formatSize(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
  }
}

enum PenEditorLayout {
  static func sizePresets(for tool: EditorTool) -> [Double] {
    switch tool {
    case .highlighter: [4.8, 7.2, 9.6, 14.4, 19.2]
    case .marker: [1.2, 1.8, 2.4, 3.6, 4.8]
    default: [0.6, 1.2, 1.8, 2.4, 3.6]
    }
  }

  static func showsSize(for tool: EditorTool, advanced: Bool) -> Bool {
    tool == .highlighter || !advanced
  }

  static func showsOpacity(for tool: EditorTool, advanced: Bool) -> Bool {
    tool == .highlighter || advanced
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
          .accessibilityLabel("Stroke sample")
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
