import UIKit
import XCTest

@testable import MathNotes

@MainActor
final class InkEditorGestureTests: XCTestCase {
  func testModeBannerAccessibilityCombinesBookmarkHint() {
    XCTAssertEqual(
      modeBannerAccessibilityLabel(mode: "Add bookmark", showsBookmarkHint: true),
      "Add bookmark\nTap the line to mark.")
    XCTAssertEqual(
      modeBannerAccessibilityLabel(mode: "Follow links", showsBookmarkHint: false),
      "Follow links")
  }

  func testPageCounterTextIsOneBasedAndClamped() {
    XCTAssertEqual(editorPageCounterText(currentPage: 0, pageCount: 3), "1 / 3")
    XCTAssertEqual(editorPageCounterText(currentPage: 2, pageCount: 3), "3 / 3")
    XCTAssertEqual(editorPageCounterText(currentPage: 8, pageCount: 3), "3 / 3")
    XCTAssertEqual(editorPageCounterText(currentPage: -1, pageCount: 0), "1 / 1")
  }

  func testHardwareKeyboardCommandsUseIPadConventions() {
    let controller = InkEditorViewController(document: EngineDocument(seed: 105))
    let commands = controller.keyCommands ?? []

    func contains(_ input: String, _ modifiers: UIKeyModifierFlags) -> Bool {
      commands.contains { $0.input == input && $0.modifierFlags == modifiers }
    }

    XCTAssertTrue(contains("s", .command))
    XCTAssertTrue(contains("z", .command))
    XCTAssertTrue(contains("z", .command.union(.shift)))
    XCTAssertTrue(contains("y", .command))
    XCTAssertTrue(contains("a", .command))
    XCTAssertTrue(contains("c", .command))
    XCTAssertTrue(contains("x", .command))
    XCTAssertTrue(contains("v", .command))
    XCTAssertTrue(contains("d", .command))
    XCTAssertTrue(contains(UIKeyCommand.inputDelete, []))
    XCTAssertTrue(contains(UIKeyCommand.inputEscape, []))
  }

  func testSelectionBarExposesClearSelectionTarget() throws {
    let controller = InkEditorViewController(document: EngineDocument(seed: 106))
    controller.loadViewIfNeeded()

    let button = try XCTUnwrap(findButton(in: controller.view, label: "Clear selection"))
    XCTAssertTrue(button.constraints.contains {
      $0.firstAttribute == .width && abs($0.constant - 44) < 0.01
    })
    XCTAssertTrue(button.constraints.contains {
      $0.firstAttribute == .height && abs($0.constant - 44) < 0.01
    })
  }

  func testSelectionActionsWrapInsideNarrowPane() {
    let wrap = SelectionActionWrapView(spacing: 2, contentInset: 2)
    var buttons: [UIButton] = []
    for _ in 0..<5 {
      let button = UIButton(type: .system)
      button.widthAnchor.constraint(equalToConstant: 44).isActive = true
      button.heightAnchor.constraint(equalToConstant: 44).isActive = true
      wrap.addArrangedSubview(button)
      buttons.append(button)
    }

    XCTAssertEqual(
      wrap.sizeThatFits(CGSize(width: 140, height: 1_000)),
      CGSize(width: 140, height: 94))

    buttons[3].isHidden = true
    buttons[4].isHidden = true
    XCTAssertEqual(
      wrap.sizeThatFits(CGSize(width: 140, height: 1_000)),
      CGSize(width: 140, height: 48))
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

  func testCanvasSeparatesPrimaryAndSecondaryPointerTaps() throws {
    let controller = InkEditorViewController(document: EngineDocument(seed: 111))
    controller.loadViewIfNeeded()

    let taps = gestureRecognizers(in: controller.view)
      .compactMap { $0 as? UITapGestureRecognizer }
    let primary = try XCTUnwrap(taps.first { $0.buttonMaskRequired == .primary })
    let secondary = try XCTUnwrap(taps.first { $0.buttonMaskRequired == .secondary })

    XCTAssertEqual(primary.allowedTouchTypes,
      [NSNumber(value: UITouch.TouchType.direct.rawValue)])
    XCTAssertFalse(primary.cancelsTouchesInView)
    XCTAssertEqual(secondary.numberOfTouchesRequired, 1)
    XCTAssertEqual(secondary.numberOfTapsRequired, 1)
  }

  func testEditorInstallsNativeHeldPullFooter() throws {
    let controller = InkEditorViewController(document: EngineDocument(seed: 110))
    controller.loadViewIfNeeded()
    let scroll = try XCTUnwrap(findScrollView(in: controller.view))
    let footer = try XCTUnwrap(findSubview(in: scroll) { view in
      String(describing: type(of: view)).contains("MJRefreshBackNormalFooter")
    })

    XCTAssertEqual(footer.frame.height, 96, accuracy: 0.01)
  }

  func testUIKitOwnsDirectTouchPanPinchAndZoomBounds() throws {
    let controller = InkEditorViewController(document: EngineDocument(seed: 109))
    controller.loadViewIfNeeded()
    let scroll = try XCTUnwrap(findScrollView(in: controller.view))
    let direct = NSNumber(value: UITouch.TouchType.direct.rawValue)

    XCTAssertEqual(scroll.minimumZoomScale, 0.25, accuracy: 0.0001)
    XCTAssertEqual(scroll.maximumZoomScale, 8, accuracy: 0.0001)
    XCTAssertTrue(scroll.alwaysBounceVertical)
    XCTAssertTrue(scroll.alwaysBounceHorizontal)
    XCTAssertTrue(scroll.bouncesZoom)
    XCTAssertEqual(scroll.panGestureRecognizer.allowedTouchTypes, [direct])
    XCTAssertEqual(scroll.pinchGestureRecognizer?.allowedTouchTypes, [direct])
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

  func testPencilStrokeSuppressesPalmScrollPan() {
    let controller = InkEditorViewController(document: EngineDocument(seed: 107))
    controller.loadViewIfNeeded()
    let scroll = findScrollView(in: controller.view)

    XCTAssertEqual(scroll?.panGestureRecognizer.isEnabled, true)
    controller.setPencilStrokeActive(true)
    XCTAssertEqual(scroll?.panGestureRecognizer.isEnabled, false)
    controller.setPencilStrokeActive(false)
    XCTAssertEqual(scroll?.panGestureRecognizer.isEnabled, true)
  }

  func testEditorRegistersApplePencilInteraction() {
    let controller = InkEditorViewController(document: EngineDocument(seed: 102))
    controller.loadViewIfNeeded()

    XCTAssertEqual(
      controller.view.interactions.compactMap { $0 as? UIPencilInteraction }.count,
      1)
  }

  func testPencilHoverPreviewRejectsPointerHover() throws {
    let controller = InkEditorViewController(document: EngineDocument(seed: 108))
    controller.loadViewIfNeeded()

    let hover = try XCTUnwrap(
      gestureRecognizers(in: controller.view)
        .compactMap { $0 as? UIHoverGestureRecognizer }
        .first)
    XCTAssertEqual(
      hover.allowedTouchTypes,
      [NSNumber(value: UITouch.TouchType.pencil.rawValue)])
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

  private func findSubview(in view: UIView, matching predicate: (UIView) -> Bool) -> UIView? {
    if predicate(view) { return view }
    return view.subviews.lazy.compactMap { self.findSubview(in: $0, matching: predicate) }.first
  }

  private func findButton(in view: UIView, label: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityLabel == label { return button }
    return view.subviews.lazy.compactMap { self.findButton(in: $0, label: label) }.first
  }

  private func findScrollView(in view: UIView) -> UIScrollView? {
    if let scroll = view as? UIScrollView { return scroll }
    return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
  }
  func testDrawingModeEntryUsesADrawingTool() {
    XCTAssertEqual(editorToolForDrawingEntry(tool: .pen, drawingTool: .marker), .pen)
    XCTAssertEqual(editorToolForDrawingEntry(tool: .text, drawingTool: .marker), .marker)
    XCTAssertEqual(editorToolForDrawingEntry(tool: .navigate, drawingTool: .highlighter), .highlighter)
  }

}
