import CoreGraphics
import UIKit
import XCTest
@testable import MathNotes

final class PencilActionTests: XCTestCase {
  func testSwitchEraserTogglesBackToPreviousTool() {
    let erased = applyPreferredPencilAction(
      .switchEraser, tool: .marker, previousTool: .pen, point: nil)
    XCTAssertEqual(erased.tool, .eraser)
    XCTAssertEqual(erased.previousTool, .marker)

    let restored = applyPreferredPencilAction(
      .switchEraser, tool: erased.tool, previousTool: erased.previousTool, point: nil)
    XCTAssertEqual(restored.tool, .marker)
    XCTAssertEqual(restored.previousTool, .eraser)
  }

  func testSwitchPreviousSwapsCurrentAndPreviousTools() {
    let result = applyPreferredPencilAction(
      .switchPrevious, tool: .highlighter, previousTool: .pen, point: nil)
    XCTAssertEqual(result.tool, .pen)
    XCTAssertEqual(result.previousTool, .highlighter)
  }

  func testPaletteActionsUseHoverPoseOrFallbackAnchor() {
    let point = CGPoint(x: 31, y: 47)
    XCTAssertEqual(
      applyPreferredPencilAction(
        .showColorPalette, tool: .pen, previousTool: nil, point: point).paletteAnchor,
      point)
    XCTAssertEqual(
      applyPreferredPencilAction(
        .showContextualPalette, tool: .pen, previousTool: nil, point: nil).paletteAnchor,
      CGPoint(x: 88, y: 88))
  }
  func testHoverPreviewRespectsSystemPreferenceAndActiveStrokeState() {
    XCTAssertTrue(
      pencilHoverPreviewAllowed(
        preference: true, hostActive: true, pencilStrokeActive: false))
    XCTAssertFalse(
      pencilHoverPreviewAllowed(
        preference: false, hostActive: true, pencilStrokeActive: false))
    XCTAssertFalse(
      pencilHoverPreviewAllowed(
        preference: true, hostActive: false, pencilStrokeActive: false))
    XCTAssertFalse(
      pencilHoverPreviewAllowed(
        preference: true, hostActive: true, pencilStrokeActive: true))
  }

}
