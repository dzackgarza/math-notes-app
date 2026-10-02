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

struct EnginePageSize {
  let size: InkPageSize
  let orientation: InkOrientation
  let width: Double
  let height: Double
}

struct EngineHistoryStep {
  let page: Int
}

@MainActor
final class EngineDocument {
  let pointer: OpaquePointer

  private init(pointer: OpaquePointer) {
    self.pointer = pointer
  }

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

  static func builtinTemplateNames() throws -> [String] {
    var count = 0
    let countStatus = ink_builtin_template_count(&count)
    guard countStatus == INK_OK else {
      throw EngineDocumentError.operation("List built-in templates", lastError())
    }

    return try (0..<count).map { index in
      var name: UnsafePointer<CChar>?
      let status = ink_builtin_template_name(index, &name)
      guard status == INK_OK, let name else {
        throw EngineDocumentError.operation("Read built-in template name", lastError())
      }
      return String(cString: name)
    }
  }

  static func builtinTemplate(name: String, seed: UInt64) throws -> EngineDocument {
    var document: OpaquePointer?
    let status = name.withCString { nameBytes in
      ink_builtin_template_create(nameBytes, seed, &document)
    }
    guard status == INK_OK, let document else {
      throw EngineDocumentError.operation("Create built-in template", lastError())
    }
    return EngineDocument(pointer: document)
  }

  static func createFromTemplate(
    seed: UInt64,
    name: String,
    page: Data,
    pageSize: InkPageSize,
    orientation: InkOrientation
  ) throws -> EngineDocument {
    var document: OpaquePointer?
    let status = name.withCString { nameBytes in
      page.withUnsafeBytes { raw in
        ink_document_create_from_template(
          seed,
          nameBytes,
          raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
          raw.count,
          pageSize,
          orientation,
          0,
          0,
          &document)
      }
    }
    guard status == INK_OK, let document else {
      throw EngineDocumentError.operation("Create notebook from template", lastError())
    }
    return EngineDocument(pointer: document)
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

  func insertPage(at index: Int) throws {
    try check(ink_document_insert_page(pointer, index), operation: "Insert notebook page")
  }

  func appendPage() throws {
    try insertPage(at: pageCount())
  }

  func duplicatePage(at index: Int) throws {
    try check(ink_document_duplicate_page(pointer, index), operation: "Duplicate notebook page")
  }

  func movePage(from: Int, to: Int) throws {
    try check(ink_document_move_page(pointer, from, to), operation: "Move notebook page")
  }

  func pageRect(index: Int) throws -> CGRect {
    var x = 0.0
    var y = 0.0
    var width = 0.0
    var height = 0.0
    try check(
      ink_document_page_rect(pointer, index, &x, &y, &width, &height),
      operation: "Read notebook page rectangle")
    return CGRect(x: x, y: y, width: width, height: height)
  }

  func pageSize() throws -> EnginePageSize {
    var size = INK_PAGE_A4
    var orientation = INK_PORTRAIT
    var width = 0.0
    var height = 0.0
    try check(
      ink_document_page_size(pointer, &size, &orientation, &width, &height),
      operation: "Read notebook page size")
    return EnginePageSize(
      size: size,
      orientation: orientation,
      width: width,
      height: height)
  }

  func setPageSize(
    _ size: InkPageSize,
    orientation: InkOrientation,
    width: Double = 0,
    height: Double = 0
  ) throws {
    try check(
      ink_document_set_page_size(pointer, size, orientation, width, height),
      operation: "Set notebook page size")
  }

  func deletePage(at index: Int) throws {
    try check(ink_document_delete_page(pointer, index), operation: "Delete notebook page")
  }
  func undo() throws -> EngineHistoryStep? {
    var moved: Int32 = 0
    var page: Int32 = -1
    try check(ink_undo(pointer, &moved, &page), operation: "Undo")
    return moved != 0 ? EngineHistoryStep(page: Int(page)) : nil
  }

  func redo() throws -> EngineHistoryStep? {
    var moved: Int32 = 0
    var page: Int32 = -1
    try check(ink_redo(pointer, &moved, &page), operation: "Redo")
    return moved != 0 ? EngineHistoryStep(page: Int(page)) : nil
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

  func pagePNG(index: Int, width: Int32 = 240) throws -> Data {
    var bytes: UnsafePointer<UInt8>?
    var size = 0
    try check(
      ink_document_page_png(pointer, index, width, &bytes, &size),
      operation: "Render page thumbnail")
    guard size > 0, let bytes else { return Data() }
    return Data(bytes: bytes, count: size)
  }

  func exportPDF(
    title: String,
    firstPage: Int = 0,
    pageCount requestedPageCount: Int? = nil
  ) throws -> Data {
    let count: Int
    if let requestedPageCount {
      count = requestedPageCount
    } else {
      count = try pageCount() - firstPage
    }
    var spec = InkPdfExportSpec()
    spec.first_page = firstPage
    spec.page_count = count
    spec.include_links = 1
    spec.include_hidden_layers = 0

    var bytes: UnsafePointer<UInt8>?
    var size = 0
    let status = title.withCString { titleBytes in
      ink_export_pdf(pointer, titleBytes, &spec, &bytes, &size)
    }
    try check(status, operation: "Export PDF")
    guard size > 0, let bytes else { return Data() }
    return Data(bytes: bytes, count: size)
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
