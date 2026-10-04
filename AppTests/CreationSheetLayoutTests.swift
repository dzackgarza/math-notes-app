import XCTest
@testable import MathNotes

final class CreationSheetLayoutTests: XCTestCase {
  func testCreationSheetMatchesWebResponsiveMetrics() {
    XCTAssertEqual(CreationSheetLayoutMetrics.maxWidth, 720)
    XCTAssertEqual(CreationSheetLayoutMetrics.splitThreshold, 600)
    XCTAssertEqual(CreationSheetLayoutMetrics.previewWidth, 260)
    XCTAssertEqual(CreationSheetLayoutMetrics.previewHeight, 280)
  }
}
