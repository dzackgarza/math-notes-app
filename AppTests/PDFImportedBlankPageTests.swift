import InkEngine
import UIKit
import XCTest
@testable import MathNotes

final class PDFImportedBlankPageTests: XCTestCase {
  @MainActor
  func testBlankPageCanBeInsertedBetweenImportedPdfPages() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let root = NotesRootAccess(testURL: rootDirectory)
    let (reference, document) = try root.createNote(
      title: "PDF with blank",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    func background(_ markerX: CGFloat) throws -> Data {
      let image = UIGraphicsImageRenderer(size: CGSize(width: 612, height: 792)).image { context in
        UIColor.white.setFill()
        context.cgContext.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
        UIColor.black.setFill()
        context.cgContext.fill(CGRect(x: markerX, y: 40, width: 80, height: 20))
      }
      return try XCTUnwrap(image.pngData())
    }

    try document.importPageImage(
      at: 0, png: background(30), widthPt: 612, heightPt: 792)
    try document.deletePage(at: 1)
    try document.importPageImage(
      at: 1, png: background(160), widthPt: 612, heightPt: 792)
    XCTAssertEqual(try document.pageCount(), 2)

    try document.insertPage(at: 1)
    XCTAssertEqual(try document.pageCount(), 3)
    try root.save(document, notebook: reference)

    let reopened = try await NotesRootAccess(testURL: rootDirectory).load(reference)
    XCTAssertEqual(try reopened.pageCount(), 3)
    let first = try reopened.pageRect(index: 0)
    let inserted = try reopened.pageRect(index: 1)
    let last = try reopened.pageRect(index: 2)
    XCTAssertEqual(first.width, 612, accuracy: 0.01)
    XCTAssertEqual(first.height, 792, accuracy: 0.01)
    XCTAssertEqual(inserted.width, 595.28, accuracy: 0.01)
    XCTAssertEqual(inserted.height, 841.89, accuracy: 0.01)
    XCTAssertEqual(last.width, 612, accuracy: 0.01)
    XCTAssertEqual(last.height, 792, accuracy: 0.01)

    let noteURL = rootDirectory.appendingPathComponent(reference.name, isDirectory: true)
    let notebookData = try Data(contentsOf: noteURL.appendingPathComponent("notebook.json"))
    let notebook = try XCTUnwrap(
      JSONSerialization.jsonObject(with: notebookData) as? [String: Any])
    let pages = try XCTUnwrap(notebook["pages"] as? [[String: Any]])
    XCTAssertEqual(pages.count, 3)

    let svgs = try pages.map { page -> String in
      let file = try XCTUnwrap(page["file"] as? String)
      let url = file.split(separator: "/").reduce(noteURL) { partial, component in
        partial.appendingPathComponent(String(component))
      }
      return try String(contentsOf: url, encoding: .utf8)
    }
    XCTAssertTrue(svgs[0].contains("<image"))
    XCTAssertFalse(svgs[1].contains("<image"), "Inserted page must use the notebook's blank template")
    XCTAssertTrue(svgs[2].contains("<image"))
  }
}
