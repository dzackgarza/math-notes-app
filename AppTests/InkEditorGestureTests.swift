import UIKit
import XCTest

@testable import MathNotes

@MainActor
final class InkEditorGestureTests: XCTestCase {
  func testFingerHistoryGesturesUseExactDirectTouchCounts() {
    let controller = InkEditorViewController(document: EngineDocument(seed: 101))
    controller.loadViewIfNeeded()

    let direct = NSNumber(value: UITouch.TouchType.direct.rawValue)
    let historyTaps = gestureRecognizers(in: controller.view)
      .compactMap { $0 as? UITapGestureRecognizer }
      .filter { [2, 3].contains($0.numberOfTouchesRequired) }

    XCTAssertEqual(historyTaps.map(\.numberOfTouchesRequired).sorted(), [2, 3])
    for recognizer in historyTaps {
      XCTAssertEqual(recognizer.numberOfTapsRequired, 1)
      XCTAssertEqual(recognizer.allowedTouchTypes, [direct])
      XCTAssertFalse(recognizer.cancelsTouchesInView)
    }
  }

  func testEditorRegistersApplePencilInteraction() {
    let controller = InkEditorViewController(document: EngineDocument(seed: 102))
    controller.loadViewIfNeeded()

    XCTAssertEqual(
      controller.view.interactions.compactMap { $0 as? UIPencilInteraction }.count,
      1)
  }

  private func gestureRecognizers(in view: UIView) -> [UIGestureRecognizer] {
    (view.gestureRecognizers ?? []) + view.subviews.flatMap { gestureRecognizers(in: $0) }
  }
}
