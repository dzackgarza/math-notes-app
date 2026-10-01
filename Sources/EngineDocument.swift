import CoreGraphics
import InkEngine

@MainActor
final class EngineDocument {
  let pointer: OpaquePointer

  init(seed: UInt64 = 1) {
    var document: OpaquePointer?
    let status = ink_document_create(seed, &document)
    guard status == INK_OK, let document else {
      fatalError("ink_document_create failed: \(EngineDocument.lastError())")
    }
    pointer = document
  }

  deinit {
    ink_document_free(pointer)
  }

  func contentSize() -> CGSize {
    var width = 0.0
    var height = 0.0
    let status = ink_document_content_size(pointer, &width, &height)
    guard status == INK_OK else {
      fatalError("ink_document_content_size failed: \(Self.lastError())")
    }
    return CGSize(width: width, height: height)
  }

  static func lastError() -> String {
    guard let message = ink_last_error() else { return "unknown engine error" }
    return String(cString: message)
  }
}
