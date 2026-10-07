import CoreGraphics
import Foundation
import XCTest
@testable import MathNotes

final class ImageImportTests: XCTestCase {
  func testImageImportScalesToEightyPercentOfPage() throws {
    let data = Data([0, 1, 2, 3])
    let svg = try imageImportSVG(
      data: data,
      mimeType: "image/png",
      imageSize: CGSize(width: 1000, height: 500),
      pageSize: CGSize(width: 500, height: 500))

    XCTAssertTrue(svg.contains(data.base64EncodedString()))
    XCTAssertTrue(svg.contains("x=\"-401.0\""))
    XCTAssertTrue(svg.contains("y=\"-201.0\""))
    XCTAssertTrue(svg.contains("width=\"400.0\""))
    XCTAssertTrue(svg.contains("height=\"200.0\""))
  }

  func testImageImportKeepsSmallImagesAtNativeSizeAndMimeType() throws {
    let svg = try imageImportSVG(
      data: Data([4, 5, 6]),
      mimeType: "image/jpeg",
      imageSize: CGSize(width: 100, height: 50),
      pageSize: CGSize(width: 500, height: 500))

    XCTAssertTrue(svg.contains("data:image/jpeg;base64,"))
    XCTAssertTrue(svg.contains("x=\"-101.0\""))
    XCTAssertTrue(svg.contains("y=\"-51.0\""))
    XCTAssertTrue(svg.contains("width=\"100.0\""))
    XCTAssertTrue(svg.contains("height=\"50.0\""))
  }

  func testImageImportRejectsNonfiniteDimensions() {
    for invalid in [CGFloat.nan, CGFloat.infinity, -CGFloat.infinity] {
      XCTAssertThrowsError(try imageImportSVG(
        data: Data(), mimeType: "image/png",
        imageSize: CGSize(width: invalid, height: 100),
        pageSize: CGSize(width: 500, height: 500)))
      XCTAssertThrowsError(try imageImportSVG(
        data: Data(), mimeType: "image/png",
        imageSize: CGSize(width: 100, height: 100),
        pageSize: CGSize(width: 500, height: invalid)))
    }
  }

  func testImageImportRejectsInvalidDimensions() {
    XCTAssertThrowsError(
      try imageImportSVG(
        data: Data(),
        mimeType: "image/png",
        imageSize: .zero,
        pageSize: CGSize(width: 500, height: 500)))
  }
}
