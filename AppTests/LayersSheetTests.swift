import XCTest
@testable import MathNotes

final class LayersSheetTests: XCTestCase {
  func testLayerActionLabelsNameTheirLayer() {
    XCTAssertEqual(layerActionAccessibilityLabel("Rename", layerName: "Proof"), "Rename Proof")
    XCTAssertEqual(layerActionAccessibilityLabel("Hide", layerName: "Proof"), "Hide Proof")
    XCTAssertEqual(layerActionAccessibilityLabel("Unlock", layerName: "Notes"), "Unlock Notes")
    XCTAssertEqual(layerActionAccessibilityLabel("Merge down", layerName: "Ink"), "Merge down Ink")
    XCTAssertEqual(layerActionAccessibilityLabel("Delete", layerName: "Ink"), "Delete Ink")
  }
}
