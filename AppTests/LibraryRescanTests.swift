import InkEngine
import XCTest
@testable import MathNotes

final class LibraryRescanTests: XCTestCase {
  @MainActor
  func testExternalNotebookRenameAppearsOnRescan() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (original, _) = try root.createNote(
      title: "Before Rename",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    XCTAssertEqual(try root.notebooks(), [original])

    let source = directory.appendingPathComponent("Before Rename", isDirectory: true)
    let destination = directory.appendingPathComponent("After Rename", isDirectory: true)
    try FileManager.default.moveItem(at: source, to: destination)

    let rescanned = try root.notebooks()
    XCTAssertEqual(rescanned, [NotebookReference(path: ["After Rename"])])
    XCTAssertFalse(rescanned.contains(original))
  }
}
