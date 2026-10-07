import XCTest
@testable import MathNotes

final class FitScrollPositionTests: XCTestCase {
  func testFitKeepsTheLeadingDocumentCoordinate() throws {
    let coordinate = try XCTUnwrap(
      FitScrollPosition.leadingDocumentCoordinate(
        contentOffset: 216,
        leadingInset: 84,
        zoomScale: 2))
    XCTAssertEqual(coordinate, 150, accuracy: 0.001)

    XCTAssertEqual(
      FitScrollPosition.contentOffset(
        for: coordinate,
        leadingInset: 84,
        zoomScale: 1,
        minimum: -84,
        maximum: 900),
      66,
      accuracy: 0.001)
  }

  func testFitOffsetClampsToScrollableRange() {
    XCTAssertEqual(
      FitScrollPosition.contentOffset(
        for: -100,
        leadingInset: 16,
        zoomScale: 1,
        minimum: -16,
        maximum: 500),
      -16)
    XCTAssertEqual(
      FitScrollPosition.contentOffset(
        for: 1000,
        leadingInset: 16,
        zoomScale: 1,
        minimum: -16,
        maximum: 500),
      500)
  }
  func testInvalidScrollGeometryIsNotRestored() {
    XCTAssertNil(FitScrollPosition.leadingDocumentCoordinate(
      contentOffset: .infinity, leadingInset: 0, zoomScale: 1))
    XCTAssertNil(FitScrollPosition.leadingDocumentCoordinate(
      contentOffset: 0, leadingInset: 0, zoomScale: .nan))
    XCTAssertNil(FitScrollPosition.leadingDocumentCoordinate(
      contentOffset: 0, leadingInset: 0, zoomScale: 0))
  }

}
