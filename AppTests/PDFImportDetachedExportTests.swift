import CoreGraphics
import InkEngine
import PDFKit
import UIKit
import XCTest
@testable import MathNotes

final class PDFImportDetachedExportTests: XCTestCase {
  @MainActor
  func testImportedNotebookExportsAfterSourcePdfIsDeleted() async throws {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      context.beginPage()
      UIColor.white.setFill()
      context.cgContext.fill(bounds)
      UIColor.black.setFill()
      context.cgContext.fill(CGRect(x: 40, y: 52, width: 200, height: 20))
    }
    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("pdf")
    try pdf.write(to: sourceURL, options: .atomic)

    let imported = try PDFImportDocument(url: sourceURL)
    let page = try imported.rasterizedPage(at: 0)

    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: rootDirectory)
    }

    let root = NotesRootAccess(testURL: rootDirectory)
    let (reference, document) = try root.createNote(
      title: "Detached PDF",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.importPageImage(
      at: 0,
      png: page.png,
      widthPt: page.widthPt,
      heightPt: page.heightPt)
    try document.deletePage(at: 1)
    try root.save(document, notebook: reference)

    try FileManager.default.removeItem(at: sourceURL)

    let reopened = try await NotesRootAccess(testURL: rootDirectory).load(reference)
    let exported = try reopened.exportPDF(title: reference.name)
    let provider = try XCTUnwrap(CGDataProvider(data: exported as CFData))
    let exportedPDF = try XCTUnwrap(CGPDFDocument(provider))
    XCTAssertEqual(exportedPDF.numberOfPages, 1)
    let exportedPage = try XCTUnwrap(exportedPDF.page(at: 1))
    let media = exportedPage.getBoxRect(.mediaBox)
    XCTAssertEqual(media.width, bounds.width.rounded(), accuracy: 0.01)
    XCTAssertEqual(media.height, bounds.height.rounded(), accuracy: 0.01)
  }
}
