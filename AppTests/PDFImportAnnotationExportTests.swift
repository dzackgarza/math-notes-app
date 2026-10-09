import CoreGraphics
import InkEngine
import PDFKit
import UIKit
import XCTest
@testable import MathNotes

final class PDFImportAnnotationExportTests: XCTestCase {
  @MainActor
  func testImportedBackgroundAndVectorInkSurviveExport() async throws {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      context.beginPage()
      UIColor.white.setFill()
      context.cgContext.fill(bounds)
      UIColor.darkGray.setFill()
      context.cgContext.fill(CGRect(x: 36, y: 42, width: 210, height: 24))
    }
    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("pdf")
    try pdf.write(to: sourceURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let imported = try PDFImportDocument(url: sourceURL)
    let importedPage = try imported.rasterizedPage(at: 0)

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Annotated PDF",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.importPageImage(
      at: 0,
      png: importedPage.png,
      widthPt: importedPage.widthPt,
      heightPt: importedPage.heightPt)
    try document.deletePage(at: 1)

    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixtureDirectory = repository
      .appendingPathComponent("core/tests/fixtures/documents/full", isDirectory: true)
    let fixture = EngineDocument(seed: 901)
    try fixture.loadNotebook(Data(contentsOf: fixtureDirectory.appendingPathComponent("notebook.json")))
    let pageURL = fixtureDirectory
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("0001.svg")
    let fixturePage = try String(contentsOf: pageURL, encoding: .utf8)
      .replacingOccurrences(
        of: #"\n    <image id="s-pastedimage"[^>]*/>"#,
        with: "",
        options: .regularExpression)
    try fixture.loadPage(path: "pages/0001.svg", data: Data(fixturePage.utf8))
    let sourceCanvas = InkCanvasView(document: fixture)
    sourceCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    sourceCanvas.layoutIfNeeded()
    sourceCanvas.setViewTransform(.identity)
    try sourceCanvas.selectAll(page: 0)
    let selection = try XCTUnwrap(sourceCanvas.copySelection())
    XCTAssertTrue(selection.contains("mn:brush"), "Fixture selection must contain vector ink")

    let targetCanvas = InkCanvasView(document: document)
    targetCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    targetCanvas.layoutIfNeeded()
    targetCanvas.setViewTransform(.identity)
    try targetCanvas.paste(
      selection,
      at: CGPoint(x: bounds.midX, y: bounds.midY),
      placeAtPointer: true)
    try root.save(document, notebook: reference)

    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let indexData = try Data(contentsOf: noteURL.appendingPathComponent("notebook.json"))
    let index = try XCTUnwrap(JSONSerialization.jsonObject(with: indexData) as? [String: Any])
    let pages = try XCTUnwrap(index["pages"] as? [[String: Any]])
    let file = try XCTUnwrap(pages.first?["file"] as? String)
    let savedPageURL = file.split(separator: "/").reduce(noteURL) { partial, component in
      partial.appendingPathComponent(String(component))
    }
    let savedPage = try String(contentsOf: savedPageURL, encoding: .utf8)
    XCTAssertTrue(savedPage.contains("<image"), "Imported PDF background must remain embedded")
    XCTAssertTrue(savedPage.contains("mn:brush"), "Annotation must remain vector ink")

    let reopened = try await NotesRootAccess(testURL: directory).load(reference)
    let exported = try reopened.exportPDF(title: reference.name)
    let provider = try XCTUnwrap(CGDataProvider(data: exported as CFData))
    let exportedPDF = try XCTUnwrap(CGPDFDocument(provider))
    XCTAssertEqual(exportedPDF.numberOfPages, 1)
    let media = try XCTUnwrap(exportedPDF.page(at: 1)).getBoxRect(.mediaBox)
    XCTAssertEqual(media.width, bounds.width.rounded(), accuracy: 0.01)
    XCTAssertEqual(media.height, bounds.height.rounded(), accuracy: 0.01)
  }
}
