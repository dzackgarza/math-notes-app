import InkEngine
import XCTest
@testable import MathNotes

final class RootMoveTests: XCTestCase {
  @MainActor
  func testPresentedRootMoveRebasesStorageOperations() async throws {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let original = parent.appendingPathComponent("Notes", isDirectory: true)
    let moved = parent.appendingPathComponent("Renamed Notes", isDirectory: true)
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let root = NotesRootAccess(testURL: original)
    let (reference, _) = try root.createNote(
      title: "Lecture",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    XCTAssertEqual(try root.notebooks(), [reference])

    try FileManager.default.moveItem(at: original, to: moved)
    root.simulatePresentedRootMove(to: moved)

    XCTAssertEqual(root.url.standardizedFileURL, moved.standardizedFileURL)
    XCTAssertEqual(try root.notebooks(), [reference])
    let loaded1 = try await root.load(reference)
    XCTAssertEqual(try loaded1.pageCount(), 1)
  }
}
