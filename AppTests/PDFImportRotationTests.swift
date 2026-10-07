import CoreGraphics
import Foundation
import InkEngine
import PDFKit
import UIKit
import XCTest
@testable import MathNotes

final class PDFImportRotationTests: XCTestCase {
  @MainActor
  func testRotatedPDFPageKeepsDisplayedSizeThroughImportAndExport() throws {
    let sourceBounds = CGRect(x: 0, y: 0, width: 300, height: 500)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: sourceBounds.size, format: format).image { context in
      UIColor.white.setFill()
      context.cgContext.fill(sourceBounds)
      UIColor.black.setFill()
      context.cgContext.fill(CGRect(x: 30, y: 40, width: 90, height: 60))
    }
    let sourcePage = try XCTUnwrap(PDFPage(image: image))
    sourcePage.setBounds(sourceBounds, for: .mediaBox)
    sourcePage.rotation = 90
    let source = PDFDocument()
    source.insert(sourcePage, at: 0)

    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("pdf")
    try XCTUnwrap(source.dataRepresentation()).write(to: sourceURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let imported = try PDFImportDocument(url: sourceURL)
    let page = try imported.rasterizedPage(at: 0)
    let raster = try XCTUnwrap(UIImage(data: page.png)?.cgImage)
    XCTAssertEqual(raster.width, 4128)
    XCTAssertEqual(page.widthPt, 500, accuracy: 0.01)
    XCTAssertEqual(page.heightPt, 300, accuracy: 0.01)
    let expectedRasterHeight = Int((300.0 / 500.0 * 4128.0).rounded())
    XCTAssertLessThanOrEqual(abs(raster.height - expectedRasterHeight), 1)

    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootDirectory) }
    let root = NotesRootAccess(testURL: rootDirectory)
    let (reference, document) = try root.createNote(
      title: "Rotated PDF",
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

    let reopened = try NotesRootAccess(testURL: rootDirectory).load(reference)
    let rect = try reopened.pageRect(index: 0)
    XCTAssertEqual(rect.width, 500, accuracy: 0.01)
    XCTAssertEqual(rect.height, 300, accuracy: 0.01)

    let exported = try reopened.exportPDF(title: reference.name)
    let provider = try XCTUnwrap(CGDataProvider(data: exported as CFData))
    let pdf = try XCTUnwrap(CGPDFDocument(provider))
    let media = try XCTUnwrap(pdf.page(at: 1)).getBoxRect(.mediaBox)
    XCTAssertEqual(media.width, 500, accuracy: 0.01)
    XCTAssertEqual(media.height, 300, accuracy: 0.01)
  }
}

extension PDFImportRotationTests {
  @MainActor
  func testPDFImportUsesVisibleCropBoxRatherThanMediaBox() throws {
    let source = PDFDocument()
    let page = try XCTUnwrap(PDFPage(image: UIGraphicsImageRenderer(
      size: CGSize(width: 600, height: 800)).image { _ in }))
    page.setBounds(CGRect(x: 0, y: 0, width: 600, height: 800), for: .mediaBox)
    page.setBounds(CGRect(x: 50, y: 100, width: 300, height: 400), for: .cropBox)
    source.insert(page, at: 0)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    try XCTUnwrap(source.dataRepresentation()).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let imported = try PDFImportDocument(url: url).rasterizedPage(at: 0, maxWidthPixels: 300)
    XCTAssertEqual(imported.widthPt, 300, accuracy: 0.01)
    XCTAssertEqual(imported.heightPt, 400, accuracy: 0.01)
    let raster = try XCTUnwrap(UIImage(data: imported.png)?.cgImage)
    XCTAssertEqual(raster.width, 300)
    XCTAssertEqual(raster.height, 400)
  }
}
