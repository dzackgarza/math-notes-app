import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class NotebookStorageTests: XCTestCase {
  @MainActor
  func testAppendPageUsesTheSharedDocumentAndBecomesDirty() throws {
    let document = EngineDocument(seed: 7)
    XCTAssertEqual(try document.pageCount(), 1)
    try document.markSaved()

    try document.appendPage()

    XCTAssertEqual(try document.pageCount(), 2)
    XCTAssertEqual(
      try document.dirtyFiles().map(\.path),
      ["notebook.json", "pages/0002.svg"])
  }

  @MainActor
  func testPageManagementUsesTheSharedDocumentHistory() throws {
    let document = EngineDocument(seed: 13)

    try document.insertPage(at: 0)
    XCTAssertEqual(try document.pageCount(), 2)

    try document.duplicatePage(at: 0)
    XCTAssertEqual(try document.pageCount(), 3)

    try document.deletePage(at: 1)
    XCTAssertEqual(try document.pageCount(), 2)

    XCTAssertTrue(try document.undo())
    XCTAssertEqual(try document.pageCount(), 3)
  }

  @MainActor
  func testPDFExportUsesTheSharedDocument() throws {
    let document = EngineDocument(seed: 17)

    let pdf = try document.exportPDF(title: "Export Test")

    XCTAssertGreaterThan(pdf.count, 5)
    XCTAssertEqual(String(decoding: pdf.prefix(5), as: UTF8.self), "%PDF-")
  }

  @MainActor
  func testBuiltinTemplateFactoryMatchesTheSharedCreationPath() throws {
    XCTAssertEqual(
      try EngineDocument.builtinTemplateNames(),
      [
        "blank",
        "lined-wide",
        "lined-medium",
        "lined-narrow",
        "grid-coarse",
        "grid-medium",
        "grid-fine",
        "dotted",
      ])

    let template = try EngineDocument.builtinTemplate(name: "dotted", seed: 23)
    let templateChanges = try template.dirtyFiles()
    let pageChange = try XCTUnwrap(
      templateChanges.first { $0.path == "pages/0001.svg" })
    guard case let .write(page) = pageChange.kind else {
      return XCTFail("The built-in template page was not writable data")
    }

    let note = try EngineDocument.createFromTemplate(
      seed: 29,
      name: "dotted",
      page: page,
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let noteIndex = try XCTUnwrap(
      try note.dirtyFiles().first { $0.path == "notebook.json" })
    guard case let .write(indexBytes) = noteIndex.kind else {
      return XCTFail("The new notebook index was not writable data")
    }
    let index = try XCTUnwrap(
      JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    XCTAssertEqual(index["template"] as? String, "dotted")
    XCTAssertEqual(index["pageSize"] as? String, "A4")
  }

  func testLibraryNameValidationMatchesTheWebRules() throws {
    XCTAssertEqual(try validatedLibraryName("  Stable pairs  "), "Stable pairs")
    XCTAssertThrowsError(try validatedLibraryName(""))
    XCTAssertThrowsError(try validatedLibraryName(".trash"))
    XCTAssertThrowsError(try validatedLibraryName("A/B"))
    XCTAssertThrowsError(try validatedLibraryName("A\\B"))
  }

  func testWritesAssetsThenPagesThenNotebookMetadataThenDeletes() {
    let changes = [
      EngineFileChange(path: "pages/0002.svg", kind: .delete),
      EngineFileChange(path: "notebook.json", kind: .write(Data("index".utf8))),
      EngineFileChange(path: "pages/0001.svg", kind: .write(Data("page".utf8))),
      EngineFileChange(path: "assets/diagram.png", kind: .write(Data([1, 2, 3]))),
      EngineFileChange(path: "assets/old.png", kind: .delete),
    ]

    XCTAssertEqual(
      orderedNotebookChanges(changes).map(\.path),
      [
        "assets/diagram.png",
        "pages/0001.svg",
        "notebook.json",
        "assets/old.png",
        "pages/0002.svg",
      ])
  }
}
