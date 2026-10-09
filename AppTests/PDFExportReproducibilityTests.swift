import CoreGraphics
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
  @MainActor
  func testSharedFixturesExportEveryPageAtItsDocumentSize() async throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixtures = repository.appendingPathComponent(
      "core/tests/fixtures/documents", isDirectory: true)

    for fixtureName in ["full", "custom-size"] {
      let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: rootDirectory) }

      let reference = NotebookReference(path: [fixtureName])
      try FileManager.default.copyItem(
        at: fixtures.appendingPathComponent(fixtureName, isDirectory: true),
        to: rootDirectory.appendingPathComponent(fixtureName, isDirectory: true))
      let document = try await NotesRootAccess(testURL: rootDirectory).load(reference)
      let exported = try document.exportPDF(title: fixtureName)
      let provider = try XCTUnwrap(CGDataProvider(data: exported as CFData))
      let pdf = try XCTUnwrap(CGPDFDocument(provider))
      let pageCount = try document.pageCount()

      XCTAssertEqual(pdf.numberOfPages, pageCount, fixtureName)
      for index in 0..<pageCount {
        let expected = try document.pageRect(index: index)
        let page = try XCTUnwrap(pdf.page(at: index + 1))
        let media = page.getBoxRect(.mediaBox)
        XCTAssertEqual(media.width, expected.width.rounded(), accuracy: 0.01, fixtureName)
        XCTAssertEqual(media.height, expected.height.rounded(), accuracy: 0.01, fixtureName)
      }
    }
  }

}
