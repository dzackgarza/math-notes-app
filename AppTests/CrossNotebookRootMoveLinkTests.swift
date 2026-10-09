import InkEngine
import XCTest
@testable import MathNotes

final class CrossNotebookRootMoveLinkTests: XCTestCase {
  @MainActor
  func testCrossNotebookLinkStillOpensAfterWholeRootMoves() async throws {
    let parent = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let original = parent.appendingPathComponent("Notes", isDirectory: true)
    let moved = parent.appendingPathComponent("Moved Notes", isDirectory: true)
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let root = NotesRootAccess(testURL: original)
    let seminar = try root.createFolder(
      parent: FolderReference(path: []),
      name: "Seminar")
    let references = try root.createFolder(
      parent: FolderReference(path: []),
      name: "References")
    let (source, sourceDocument) = try root.createNote(
      title: "Day 1",
      parent: seminar,
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let (target, targetDocument) = try root.createNote(
      title: "K3 notes",
      parent: references,
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let sourcePage = try XCTUnwrap(
      sourceDocument.navigation().first { $0.id.isEmpty && $0.href.isEmpty })
    let targetPage = try XCTUnwrap(
      targetDocument.navigation().first { $0.id.isEmpty && $0.href.isEmpty })
    let href = try NotebookLink.href(
      source: source,
      sourceFile: sourcePage.file,
      target: target,
      mark: targetPage)

    try coordinatedMove(original, to: moved)
    awaitRootURL(root, moved, in: self)

    let resolved = try NotebookLink.resolve(
      source: source,
      sourceFile: sourcePage.file,
      href: href)
    guard case let .page(reference, file, id) = resolved else {
      return XCTFail("Expected an in-root notebook link, got \(resolved)")
    }
    XCTAssertEqual(reference, target)
    XCTAssertEqual(file, targetPage.file)
    XCTAssertTrue(id.isEmpty)
    XCTAssertEqual(root.url.standardizedFileURL, moved.standardizedFileURL)
    let loaded1 = try await root.load(reference)
    XCTAssertEqual(try loaded1.pageCount(), 1)
  }
}
