import CoreGraphics
import Foundation
import XCTest
@testable import MathNotes

final class PDFLinkAnnotationTests: XCTestCase {
  @MainActor
  func testBookmarkAndInternalLinkExportAsPDFAnnotations() throws {
    let document = EngineDocument(seed: 0x4C494E4B)
    let canvas = InkCanvasView(document: document)
    canvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    canvas.layoutIfNeeded()
    canvas.setViewTransform(.identity)

    try canvas.editText(
      EngineTextProperties(content: "Destination", width: 160, rtl: false),
      at: CGPoint(x: 90, y: 120),
      existing: false)
    XCTAssertTrue(try canvas.selectText(at: CGPoint(x: 96, y: 126)))
    try canvas.bookmarkSelection()
    let bookmark = try XCTUnwrap(
      document.navigation().first { !$0.id.isEmpty && $0.href.isEmpty })
    XCTAssertTrue(bookmark.id.hasPrefix("b-"))

    try canvas.editText(
      EngineTextProperties(content: "Go to destination", width: 190, rtl: false),
      at: CGPoint(x: 90, y: 240),
      existing: false)
    XCTAssertTrue(try canvas.selectText(at: CGPoint(x: 96, y: 246)))
    try canvas.linkSelection("#\(bookmark.id)")

    let links = try document.navigation().filter { !$0.href.isEmpty }
    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links[0].href, "#\(bookmark.id)")

    let pdf = try document.exportPDF(title: "Linked PDF")
    let text = String(decoding: pdf, as: UTF8.self)
    XCTAssertTrue(text.contains("/Annots"), "PDF export must contain a page annotation array")
    XCTAssertTrue(text.contains("/Dest"), "PDF export must contain an internal destination link")
  }
}
