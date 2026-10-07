import XCTest
@testable import MathNotes

final class KeyboardDrawingModeTests: XCTestCase {
  func testKeyboardAndGestureEditingRequireFocusedActiveEditorOutsideDrawingMode() {
    XCTAssertTrue(
      editorKeyboardEditingAllowed(
        active: true, focused: true, figureCaptureActive: false, figureCompleting: false))
    XCTAssertFalse(
      editorKeyboardEditingAllowed(
        active: true, focused: true, figureCaptureActive: true, figureCompleting: false))
    XCTAssertFalse(
      editorKeyboardEditingAllowed(
        active: true, focused: true, figureCaptureActive: false, figureCompleting: true))
    XCTAssertFalse(
      editorKeyboardEditingAllowed(
        active: false, focused: true, figureCaptureActive: false, figureCompleting: false))
    XCTAssertFalse(
      editorKeyboardEditingAllowed(
        active: true, focused: false, figureCaptureActive: false, figureCompleting: false))
  }
}
