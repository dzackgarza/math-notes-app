import Foundation
import InkEngine

@MainActor
struct EditorPenLibrary {
  var pen: InkToolSettings
  var marker: InkToolSettings
  var highlighter: InkToolSettings
  var palette: [UInt32]
  var saved: [InkToolSettings]

  static let defaults: EditorPenLibrary = {
    do {
      return try EditorPenLibrary(json: defaultJSON())
    } catch {
      fatalError("Default pen file is invalid: \(error.localizedDescription)")
    }
  }()

  init(
    pen: InkToolSettings,
    marker: InkToolSettings,
    highlighter: InkToolSettings,
    palette: [UInt32],
    saved: [InkToolSettings]
  ) {
    self.pen = pen
    self.marker = marker
    self.highlighter = highlighter
    self.palette = palette
    self.saved = saved
  }

  init(json: Data) throws {
    var parsed: UnsafePointer<InkPenFile>?
    let status = json.withUnsafeBytes { raw in
      ink_pens_read(
        raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
        raw.count,
        &parsed)
    }
    guard status == INK_OK, let parsed else {
      throw EngineDocumentError.operation("Read pen settings", EngineDocument.lastError())
    }

    let value = parsed.pointee
    pen = value.pen
    marker = value.marker
    highlighter = value.highlighter
    palette = Self.copyArray(value.palette, count: value.palette_count)
    saved = Self.copyArray(value.saved, count: value.saved_count)
  }

  var tools: EditorPenSet {
    EditorPenSet(pen: pen, marker: marker, highlighter: highlighter)
  }

  func settings(for tool: EditorTool) -> InkToolSettings {
    switch tool {
    case .pen: pen
    case .marker: marker
    case .highlighter: highlighter
    case .eraser, .lasso, .space: pen
    }
  }

  mutating func setSettings(_ settings: InkToolSettings, for tool: EditorTool) {
    switch tool {
    case .pen: pen = settings
    case .marker: marker = settings
    case .highlighter: highlighter = settings
    case .eraser, .lasso, .space: break
    }
  }

  func json() throws -> Data {
    var file = InkPenFile()
    file.pen = pen
    file.marker = marker
    file.highlighter = highlighter

    return try palette.withUnsafeBufferPointer { paletteBuffer in
      try saved.withUnsafeBufferPointer { savedBuffer in
        file.palette = paletteBuffer.baseAddress
        file.palette_count = paletteBuffer.count
        file.saved = savedBuffer.baseAddress
        file.saved_count = savedBuffer.count

        var json: UnsafePointer<UInt8>?
        var size = 0
        let status = ink_pens_write(&file, &json, &size)
        guard status == INK_OK, let json else {
          throw EngineDocumentError.operation("Write pen settings", EngineDocument.lastError())
        }
        return Data(bytes: json, count: size)
      }
    }
  }

  static func defaultJSON() throws -> Data {
    var json: UnsafePointer<UInt8>?
    var size = 0
    let status = ink_pens_default(&json, &size)
    guard status == INK_OK, let json else {
      throw EngineDocumentError.operation("Read default pen settings", EngineDocument.lastError())
    }
    return Data(bytes: json, count: size)
  }

  static func previewPNG(
    _ settings: InkToolSettings,
    width: Int32,
    height: Int32,
    scale: Float
  ) throws -> Data {
    var settings = settings
    var png: UnsafePointer<UInt8>?
    var size = 0
    let status = ink_pens_preview_png(
      &settings,
      width,
      height,
      scale,
      &png,
      &size)
    guard status == INK_OK, let png else {
      throw EngineDocumentError.operation("Render pen preview", EngineDocument.lastError())
    }
    return Data(bytes: png, count: size)
  }

  private static func copyArray<T>(_ pointer: UnsafePointer<T>?, count: Int) -> [T] {
    guard count > 0, let pointer else { return [] }
    return Array(UnsafeBufferPointer(start: pointer, count: count))
  }
}
