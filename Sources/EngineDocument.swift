import CoreGraphics
import Foundation
import InkEngine

struct EngineFileChange: Equatable {
  enum Kind: Equatable {
    case write(Data)
    case delete
  }

  let path: String
  let kind: Kind
}

enum EngineDocumentError: LocalizedError {
  case operation(String, String)

  var errorDescription: String? {
    switch self {
    case let .operation(operation, message):
      return "\(operation): \(message)"
    }
  }
}

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

  func pageCount() throws -> Int {
    var count = 0
    try check(ink_document_page_count(pointer, &count), operation: "Count notebook pages")
    return count
  }

  func appendPage() throws {
    let count = try pageCount()
    try check(ink_document_insert_page(pointer, count), operation: "Add notebook page")
  }

  func undo() throws -> Bool {
    var moved: Int32 = 0
    var page: Int32 = -1
    try check(ink_undo(pointer, &moved, &page), operation: "Undo")
    return moved != 0
  }

  func redo() throws -> Bool {
    var moved: Int32 = 0
    var page: Int32 = -1
    try check(ink_redo(pointer, &moved, &page), operation: "Redo")
    return moved != 0
  }

  func loadNotebook(_ data: Data) throws {
    let status = withBytes(data) { bytes, count in
      ink_document_load_notebook(pointer, bytes, count)
    }
    try check(status, operation: "Load notebook")
  }

  func loadPage(path: String, data: Data) throws {
    let status = path.withCString { pathBytes in
      withBytes(data) { bytes, count in
        ink_document_load_page(pointer, pathBytes, bytes, count)
      }
    }
    if status == INK_ERROR_PARSE {
      return
    }
    try check(status, operation: "Load \(path)")
  }

  func loadAsset(path: String, data: Data) throws {
    let status = path.withCString { pathBytes in
      withBytes(data) { bytes, count in
        ink_document_load_asset(pointer, pathBytes, bytes, count)
      }
    }
    try check(status, operation: "Load \(path)")
  }

  func setTemplate(name: String, page: Data) throws {
    let status = name.withCString { nameBytes in
      withBytes(page) { bytes, count in
        ink_document_set_template(pointer, nameBytes, bytes, count)
      }
    }
    try check(status, operation: "Load template \(name)")
  }

  func dirtyFiles() throws -> [EngineFileChange] {
    var files: UnsafePointer<InkFile>?
    var count = 0
    try check(
      ink_document_dirty_files(pointer, &files, &count),
      operation: "Collect changed notebook files")

    guard count > 0, let files else { return [] }
    return (0..<count).map { index in
      let file = files.advanced(by: index).pointee
      let path = String(cString: file.path)
      if file.kind == UInt32(INK_FILE_DELETE.rawValue) {
        return EngineFileChange(path: path, kind: .delete)
      }
      let data = file.size == 0 ? Data() : Data(bytes: file.bytes, count: file.size)
      return EngineFileChange(path: path, kind: .write(data))
    }
  }

  func markSaved() throws {
    try check(ink_document_mark_saved(pointer), operation: "Mark notebook saved")
  }

  static func lastError() -> String {
    guard let message = ink_last_error() else { return "unknown engine error" }
    return String(cString: message)
  }

  private func withBytes<T>(
    _ data: Data,
    _ body: (UnsafePointer<UInt8>?, Int) -> T
  ) -> T {
    data.withUnsafeBytes { raw in
      body(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count)
    }
  }

  private func check(_ status: InkStatus, operation: String) throws {
    guard status != INK_OK else { return }
    throw EngineDocumentError.operation(operation, Self.lastError())
  }
}
