import CoreGraphics
import InkEngine
import XCTest
@testable import MathNotes

final class TextPersistenceTests: XCTestCase {
  @MainActor
  func testMultilineComplexScriptTextSurvivesSaveAndReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Complex text",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let content = "שלום עולם\nمرحبا بالعالم\nनमस्ते दुनिया"
    let properties = EngineTextProperties(content: content, width: 220, rtl: true)
    let canvas = InkCanvasView(document: document)
    canvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    canvas.layoutIfNeeded()
    canvas.setViewTransform(.identity)
    let page = try document.pageRect(index: 0)
    let point = CGPoint(x: page.minX + 96, y: page.minY + 120)
    try canvas.editText(properties, at: point, existing: false)
    try root.save(document, notebook: reference)

    let reopened = try NotesRootAccess(testURL: directory).load(reference)
    let reopenedCanvas = InkCanvasView(document: reopened)
    reopenedCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    reopenedCanvas.layoutIfNeeded()
    reopenedCanvas.setViewTransform(.identity)
    XCTAssertTrue(try reopenedCanvas.selectText(at: CGPoint(x: point.x + 4, y: point.y + 4)))

    let restored = try reopenedCanvas.textProperties()
    XCTAssertEqual(restored.content, content)
    XCTAssertEqual(restored.width, properties.width, accuracy: 0.001)
    XCTAssertTrue(restored.rtl)
    XCTAssertFalse(try reopened.pagePNG(index: 0, width: 256).isEmpty)
  }
}
