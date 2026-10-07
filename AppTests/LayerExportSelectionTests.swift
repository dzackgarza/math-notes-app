import CoreGraphics
import Foundation
import XCTest
@testable import MathNotes

final class LayerExportSelectionTests: XCTestCase {
  @MainActor
  func testPDFExportIncludesOnlySelectedLayers() throws {
    let document = EngineDocument(seed: 91)
    let notebook = """
      {
        "format": "math-notes",
        "version": 1,
        "title": "Layer export",
        "pageSize": "A4",
        "template": "blank",
        "layers": [
          { "id": "l-red", "name": "Red", "hidden": false, "locked": false },
          { "id": "l-blue", "name": "Blue", "hidden": false, "locked": false }
        ],
        "pages": [
          { "id": "p-layer-export", "file": "pages/0001.svg" }
        ]
      }
      """
    let page = """
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:mn="https://github.com/dzackgarza/math-notes-app/ns/1" id="p-layer-export" width="210mm" height="297mm" viewBox="0 0 595.28 841.89">
        <metadata />
        <g id="background" mn:ruling="blank" mn:y-ruling="28.8" mn:y-offset="0" mn:x-ruling="0" mn:margin-left="0">
          <rect width="595.28" height="841.89" fill="#FFFFFF" />
        </g>
        <g id="l-red">
          <rect id="s-red-layer" class="mn-shape" fill="none" stroke="#FF0000" stroke-width="20" x="40" y="40" width="140" height="140" />
        </g>
        <g id="l-blue">
          <rect id="s-blue-layer" class="mn-shape" fill="none" stroke="#0000FF" stroke-width="20" x="320" y="40" width="140" height="140" />
        </g>
      </svg>
      """

    try document.loadNotebook(Data(notebook.utf8))
    try document.loadPage(path: "pages/0001.svg", data: Data(page.utf8), allowParseError: false)

    let redOnly = try document.exportPDF(title: "Red", layerIDs: ["l-red"])
    let blueOnly = try document.exportPDF(title: "Blue", layerIDs: ["l-blue"])
    let both = try document.exportPDF(title: "Both", layerIDs: ["l-red", "l-blue"])

    let redCounts = try colorCounts(redOnly)
    XCTAssertGreaterThan(redCounts.red, 100)
    XCTAssertEqual(redCounts.blue, 0)

    let blueCounts = try colorCounts(blueOnly)
    XCTAssertEqual(blueCounts.red, 0)
    XCTAssertGreaterThan(blueCounts.blue, 100)

    let bothCounts = try colorCounts(both)
    XCTAssertGreaterThan(bothCounts.red, 100)
    XCTAssertGreaterThan(bothCounts.blue, 100)
  }

  private func colorCounts(_ pdf: Data) throws -> (red: Int, blue: Int) {
    let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
    let document = try XCTUnwrap(CGPDFDocument(provider))
    let page = try XCTUnwrap(document.page(at: 1))
    let media = page.getBoxRect(.mediaBox)
    let width = max(1, Int(media.width.rounded()))
    let height = max(1, Int(media.height.rounded()))
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    try pixels.withUnsafeMutableBytes { raw in
      let context = try XCTUnwrap(
        CGContext(
          data: raw.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: bitmapInfo))
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.concatenate(
        page.getDrawingTransform(
          .mediaBox,
          rect: CGRect(x: 0, y: 0, width: width, height: height),
          rotate: 0,
          preserveAspectRatio: true))
      context.drawPDFPage(page)
    }

    var red = 0
    var blue = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let r = Int(pixels[offset])
      let g = Int(pixels[offset + 1])
      let b = Int(pixels[offset + 2])
      if r > 180, g < 100, b < 100 { red += 1 }
      if b > 180, r < 100, g < 100 { blue += 1 }
    }
    return (red, blue)
  }
}
