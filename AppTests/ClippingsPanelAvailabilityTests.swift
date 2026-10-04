import XCTest
@testable import MathNotes

final class ClippingsPanelAvailabilityTests: XCTestCase {
  func testSelectionAndDrawingMatchWebClippingPanelRules() {
    let selected = ClippingsPanelAvailability(selectionActive: true, drawing: false)
    XCTAssertTrue(selected.canSaveSelection)
    XCTAssertTrue(selected.canInsert)
    XCTAssertTrue(selected.canAcceptDrop)

    let drawing = ClippingsPanelAvailability(selectionActive: true, drawing: true)
    XCTAssertFalse(drawing.canSaveSelection)
    XCTAssertFalse(drawing.canInsert)
    XCTAssertFalse(drawing.canAcceptDrop)

    XCTAssertFalse(
      ClippingsPanelAvailability(selectionActive: false, drawing: false).canSaveSelection)
  }
}
