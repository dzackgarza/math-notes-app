import CoreGraphics
import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class InsertSpacePersistenceTests: XCTestCase {
  @MainActor
  func testVerticalInsertSpaceOverflowSurvivesIPadSaveAndReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Insert Space Persistence",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let input = try MetalInputTestHarness(document: document)
    try input.setTool(EditorPenSet.defaults.marker)
    let page = try document.pageRect(index: 0)
    try input.drag(
      from: CGPoint(x: page.minX + 100, y: page.minY + 800),
      to: CGPoint(x: page.minX + 220, y: page.minY + 800),
      startTime: 1_000)

    try input.setSelector(INK_SELECTOR_SPACE_VERTICAL)
    try input.drag(
      from: CGPoint(x: page.minX + 300, y: page.minY + 700),
      to: CGPoint(x: page.minX + 300, y: page.minY + 820),
      startTime: 2_000)

    XCTAssertEqual(try document.pageCount(), 2)
    try root.save(document, notebook: reference)

    let reopened = try await NotesRootAccess(testURL: directory).load(reference)
    XCTAssertEqual(try reopened.pageCount(), 2)
    let reopenedCanvas = InkCanvasView(document: reopened)
    reopenedCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1600)
    reopenedCanvas.layoutIfNeeded()
    reopenedCanvas.setViewTransform(.identity)
    try reopenedCanvas.selectAll(page: 1)
    let movedInk = try XCTUnwrap(reopenedCanvas.copySelection())
    XCTAssertTrue(movedInk.contains("mn:brush"), "overflowed ink must remain editable after reopen")
  }
}
