import CoreGraphics
import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class RuledEraserPersistenceTests: XCTestCase {
  @MainActor
  func testRuledEraseOnBlankPaperSurvivesSaveAndKeepsPaperBlank() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Ruled Erase Persistence",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let page = try document.pageRect(index: 0)
    let input = try MetalInputTestHarness(document: document)
    try input.setTool(EditorPenSet.defaults.marker)

    try input.drag(
      from: CGPoint(x: page.minX + 200, y: page.minY + 200),
      to: CGPoint(x: page.minX + 270, y: page.minY + 200),
      startTime: 1_000)
    try input.drag(
      from: CGPoint(x: page.minX + 360, y: page.minY + 200),
      to: CGPoint(x: page.minX + 430, y: page.minY + 200),
      startTime: 2_000)
    try input.drag(
      from: CGPoint(x: page.minX + 200, y: page.minY + 320),
      to: CGPoint(x: page.minX + 270, y: page.minY + 320),
      startTime: 3_000)

    try input.setSelector(INK_SELECTOR_RULED_ERASE)
    try input.drag(
      from: CGPoint(x: page.minX + 150, y: page.minY + 200),
      to: CGPoint(x: page.minX + 300, y: page.minY + 200),
      startTime: 4_000)
    try root.save(document, notebook: reference)

    let noteDirectory = directory.appendingPathComponent(reference.name, isDirectory: true)
    let savedPage = try String(
      contentsOf: noteDirectory.appendingPathComponent("pages/0001.svg"),
      encoding: .utf8)
    XCTAssertTrue(savedPage.contains("mn:ruling=\"blank\""))

    let reopened = try NotesRootAccess(testURL: directory).load(reference)
    let reopenedCanvas = InkCanvasView(document: reopened)
    reopenedCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    reopenedCanvas.layoutIfNeeded()
    reopenedCanvas.setViewTransform(.identity)
    try reopenedCanvas.selectAll(page: 0)
    let remaining = try XCTUnwrap(reopenedCanvas.copySelection())
    XCTAssertEqual(remaining.components(separatedBy: "mn:brush=").count - 1, 2)
  }
}
