import InkEngine
import PDFKit
import UIKit
import XCTest
@testable import MathNotes

final class PDFImportMixedPageTests: XCTestCase {
  @MainActor
  func testMixedSizePdfImportsEachPageAtItsOwnSize() throws {
    let pageBounds = [
      CGRect(x: 0, y: 0, width: 595.28, height: 841.89),
      CGRect(x: 0, y: 0, width: 960, height: 540),
      CGRect(x: 0, y: 0, width: 612, height: 792),
    ]
    let pdfDocument = PDFDocument()
    for (index, bounds) in pageBounds.enumerated() {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
        UIColor.white.setFill()
        context.cgContext.fill(CGRect(origin: .zero, size: bounds.size))
        UIColor.black.setFill()
        context.cgContext.fill(
          CGRect(x: 24 + CGFloat(index * 6), y: 30, width: 120, height: 18))
      }
      let page = try XCTUnwrap(PDFPage(image: image))
      page.setBounds(bounds, for: .mediaBox)
      pdfDocument.insert(page, at: index)
    }
    let pdf = try XCTUnwrap(pdfDocument.dataRepresentation())

    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("pdf")
    try pdf.write(to: sourceURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let imported = try PDFImportDocument(url: sourceURL)
    XCTAssertEqual(imported.pageCount, pageBounds.count)
    let pages = try pageBounds.indices.map { try imported.rasterizedPage(at: $0) }
    for (page, expected) in zip(pages, pageBounds) {
      let raster = try XCTUnwrap(UIImage(data: page.png)?.cgImage)
      XCTAssertEqual(raster.width, 4128)
      XCTAssertEqual(page.widthPt, expected.width, accuracy: 0.02)
      XCTAssertEqual(page.heightPt, expected.height, accuracy: 0.02)
    }

    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let root = NotesRootAccess(testURL: rootDirectory)
    let (reference, document) = try root.createNote(
      title: "Mixed PDF",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    for (index, page) in pages.enumerated() {
      try document.importPageImage(
        at: index,
        png: page.png,
        widthPt: page.widthPt,
        heightPt: page.heightPt)
    }
    try document.deletePage(at: pages.count)
    try root.save(document, notebook: reference)

    let reopened = try NotesRootAccess(testURL: rootDirectory).load(reference)
    XCTAssertEqual(try reopened.pageCount(), pageBounds.count)
    let noteURL = rootDirectory.appendingPathComponent(reference.name, isDirectory: true)
    let notebookData = try Data(contentsOf: noteURL.appendingPathComponent("notebook.json"))
    let notebook = try XCTUnwrap(
      JSONSerialization.jsonObject(with: notebookData) as? [String: Any])
    let pageEntries = try XCTUnwrap(notebook["pages"] as? [[String: Any]])
    XCTAssertEqual(pageEntries.count, pageBounds.count)

    for (index, expected) in pageBounds.enumerated() {
      let rect = try reopened.pageRect(index: index)
      XCTAssertEqual(rect.width, expected.width, accuracy: 0.02)
      XCTAssertEqual(rect.height, expected.height, accuracy: 0.02)

      let file = try XCTUnwrap(pageEntries[index]["file"] as? String)
      let pageURL = file.split(separator: "/").reduce(noteURL) { partial, component in
        partial.appendingPathComponent(String(component))
      }
      let svg = try String(contentsOf: pageURL, encoding: .utf8)
      XCTAssertTrue(svg.contains("<image"), "Imported page \(index + 1) must retain its PDF background")
    }
  }
}
