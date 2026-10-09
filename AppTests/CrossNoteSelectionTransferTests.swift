import InkEngine
import XCTest
@testable import MathNotes

final class CrossNoteSelectionTransferTests: XCTestCase {
  @MainActor
  func testSelectionCopiesIntoAnotherNotebookAndSurvivesReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (sourceReference, source) = try root.createNote(
      title: "Source",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let (targetReference, target) = try root.createNote(
      title: "Target",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let sourceCanvas = InkCanvasView(document: source)
    sourceCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    sourceCanvas.layoutIfNeeded()
    sourceCanvas.setViewTransform(.identity)
    try sourceCanvas.editText(
      EngineTextProperties(content: "Transferred proof", width: 180, rtl: false),
      at: CGPoint(x: 72, y: 96),
      existing: false)
    try sourceCanvas.selectAll(page: 0)
    let selection = try XCTUnwrap(sourceCanvas.copySelection())
    XCTAssertTrue(selection.contains("Transferred proof"))
    try root.save(source, notebook: sourceReference)

    let targetCanvas = InkCanvasView(document: target)
    targetCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    targetCanvas.layoutIfNeeded()
    targetCanvas.setViewTransform(.identity)
    try targetCanvas.paste(
      selection,
      at: CGPoint(x: 220, y: 240),
      placeAtPointer: true)
    try root.save(target, notebook: targetReference)

    let reopened = try await NotesRootAccess(testURL: directory).load(targetReference)
    XCTAssertEqual(try reopened.pageCount(), 1)
    let noteURL = directory.appendingPathComponent(targetReference.name, isDirectory: true)
    let indexData = try Data(contentsOf: noteURL.appendingPathComponent("notebook.json"))
    let index = try XCTUnwrap(
      JSONSerialization.jsonObject(with: indexData) as? [String: Any])
    let pages = try XCTUnwrap(index["pages"] as? [[String: Any]])
    let file = try XCTUnwrap(pages.first?["file"] as? String)
    let pageURL = file.split(separator: "/").reduce(noteURL) { partial, component in
      partial.appendingPathComponent(String(component))
    }
    let bytes = try Data(contentsOf: pageURL)
    XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("Transferred proof"))
  }
}
