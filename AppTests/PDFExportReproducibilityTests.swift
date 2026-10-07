import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class PDFExportReproducibilityTests: XCTestCase {
  @MainActor
  func testRepeatedPDFExportsAreByteIdentical() throws {
    let document = EngineDocument(seed: 0x504446)
    try document.appendPage()
    try document.setPageSize(INK_PAGE_LETTER, orientation: INK_LANDSCAPE)

    let first = try document.exportPDF(title: "Reproducible Export")
    let second = try document.exportPDF(title: "Reproducible Export")

    XCTAssertFalse(first.isEmpty)
    XCTAssertEqual(first, second)
  }
}
