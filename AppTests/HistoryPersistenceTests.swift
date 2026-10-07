import CoreGraphics
import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class HistoryPersistenceTests: XCTestCase {
  @MainActor
  func testUndoRestoresPageBytesBeforeSave() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "History Persistence",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.appendPage()
    try root.save(document, notebook: reference)

    let noteDirectory = directory.appendingPathComponent(reference.name, isDirectory: true)
    let page1URL = noteDirectory.appendingPathComponent("pages/0001.svg")
    let page2URL = noteDirectory.appendingPathComponent("pages/0002.svg")
    let page1Before = try Data(contentsOf: page1URL)
    let page2Before = try Data(contentsOf: page2URL)

    let canvas = InkCanvasView(document: document)
    canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 1800)
    canvas.layoutIfNeeded()
    canvas.setViewTransform(.identity)

    let first = try document.pageRect(index: 0)
    let second = try document.pageRect(index: 1)
    try canvas.editText(
      EngineTextProperties(content: "keep this edit", width: 180, rtl: false),
      at: CGPoint(x: first.minX + 72, y: first.minY + 72),
      existing: false)
    try canvas.editText(
      EngineTextProperties(content: "undo this edit", width: 180, rtl: false),
      at: CGPoint(x: second.minX + 72, y: second.minY + 72),
      existing: false)

    let undone = try XCTUnwrap(document.undo())
    XCTAssertEqual(undone.page, 1)
    try root.save(document, notebook: reference)

    XCTAssertNotEqual(try Data(contentsOf: page1URL), page1Before)
    XCTAssertEqual(try Data(contentsOf: page2URL), page2Before)

    let reopened = try NotesRootAccess(testURL: directory).load(reference)
    XCTAssertEqual(try reopened.pageCount(), 2)
  }
}
