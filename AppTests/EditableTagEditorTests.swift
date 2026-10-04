import XCTest
@testable import MathNotes

final class EditableTagEditorTests: XCTestCase {
  func testFinalizedTagsIncludePendingTextLikeFlutterTagEditor() {
    XCTAssertEqual(
      finalizedTagValues(["Geometry"], pendingInput: "  Research  "),
      ["Geometry", "Research"])
    XCTAssertEqual(
      finalizedTagValues(["Geometry"], pendingInput: "Geometry"),
      ["Geometry"])
    XCTAssertEqual(
      finalizedTagValues(["Geometry"], pendingInput: "   "),
      ["Geometry"])
  }
}
