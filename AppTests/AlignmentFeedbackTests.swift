import XCTest
@testable import MathNotes

final class AlignmentFeedbackTests: XCTestCase {
  func testFirstAlignmentAndStepChangesNeedFeedback() {
    XCTAssertTrue(alignmentFeedbackNeeded(previous: nil, current: 0))
    XCTAssertFalse(alignmentFeedbackNeeded(previous: 0, current: 0))
    XCTAssertTrue(alignmentFeedbackNeeded(previous: 0, current: 1))
  }
}
