import UIKit
import XCTest

@testable import MathNotes

@MainActor
final class InkEditorGestureTests: XCTestCase {
  func testPageCounterTextIsOneBasedAndClamped() {
    XCTAssertEqual(editorPageCounterText(currentPage: 0, pageCount: 3), "1 / 3")
    XCTAssertEqual(editorPageCounterText(currentPage: 2, pageCount: 3), "3 / 3")
    XCTAssertEqual(editorPageCounterText(currentPage: 8, pageCount: 3), "3 / 3")
    XCTAssertEqual(editorPageCounterText(currentPage: -1, pageCount: 0), "1 / 1")
  }

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

  func testFingerDrawingRequiresTwoTouchesForScrollPan() {
    let controller = InkEditorViewController(document: EngineDocument(seed: 103))
    controller.loadViewIfNeeded()
    let scroll = findScrollView(in: controller.view)

    XCTAssertEqual(scroll?.panGestureRecognizer.minimumNumberOfTouches, 1)
    controller.setFingerDrawing(true)
    XCTAssertEqual(scroll?.panGestureRecognizer.minimumNumberOfTouches, 2)
    controller.setFingerDrawing(false)
    XCTAssertEqual(scroll?.panGestureRecognizer.minimumNumberOfTouches, 1)
  }

  func testEditorRegistersApplePencilInteraction() {
    let controller = InkEditorViewController(document: EngineDocument(seed: 102))
    controller.loadViewIfNeeded()

    XCTAssertEqual(
      controller.view.interactions.compactMap { $0 as? UIPencilInteraction }.count,
      1)
  }

  func testFittedPageClearsFloatingToolRailAndDeskMargins() throws {
    let document = EngineDocument(seed: 104)
    let controller = InkEditorViewController(document: document)
    controller.loadViewIfNeeded()
    controller.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let scroll = try XCTUnwrap(findScrollView(in: controller.view))
    let scaledWidth = document.contentSize().width * scroll.zoomScale

    XCTAssertEqual(scroll.contentInset.left, 84, accuracy: 0.5)
    XCTAssertEqual(scroll.contentInset.right, 16, accuracy: 0.5)
    XCTAssertEqual(scroll.contentInset.top, 16, accuracy: 0.5)
    XCTAssertEqual(scroll.contentInset.bottom, 16, accuracy: 0.5)
    XCTAssertEqual(
      scaledWidth + scroll.contentInset.left + scroll.contentInset.right,
      scroll.bounds.width,
      accuracy: 1)
  }

  private func gestureRecognizers(in view: UIView) -> [UIGestureRecognizer] {
    (view.gestureRecognizers ?? []) + view.subviews.flatMap { gestureRecognizers(in: $0) }
  }

  private func findScrollView(in view: UIView) -> UIScrollView? {
    if let scroll = view as? UIScrollView { return scroll }
    return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
  }
}
