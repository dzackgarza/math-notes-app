import UIKit
import WebKit
import XCTest

// SwiftUI controls are accessibility elements, not views: the tests find them
// by label in the window's accessibility tree, as VoiceOver does, and touch
// them through UIKit with Hammer.
@MainActor
extension XCTestCase {
  // The center, in screen coordinates, of the element with this label once it
  // exists (and, when asked, is enabled) and has stopped moving: a menu item
  // read while the menu opens is tapped where another item lands (the Pages
  // menu's Layers opened Pages and bookmarks, run 38025460526). Fails listing
  // every label it saw.
  func center(ofAccessibilityElement label: String, enabled: Bool = false, in window: UIWindow) throws -> CGPoint {
    var labels: [String] = []
    var previous: CGRect?
    let found = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        labels = []
        guard let element = findAccessibilityElement(label, in: window, labels: &labels),
          !enabled || !element.accessibilityTraits.contains(.notEnabled)
        else { return false }
        let frame = element.accessibilityFrame
        defer { previous = frame }
        return frame == previous
      },
      object: nil)
    let result = XCTWaiter().wait(for: [found], timeout: 20)
    labels = []
    let element = try XCTUnwrap(
      findAccessibilityElement(label, in: window, labels: &labels),
      "no accessibility element \"\(label)\" (\(result)); labels found: \(labels)")
    XCTAssertEqual(result, XCTWaiter.Result.completed, "\"\(label)\" never became \(enabled ? "enabled" : "present")")
    let frame = element.accessibilityFrame
    return CGPoint(x: frame.midX, y: frame.midY)
  }
}

// The search stays out of web views: asking a WKWebView for its
// accessibility elements makes WebKit build the page's whole accessibility
// tree on the main thread, which blocked the figure editor for 17 s while the
// test polled for its native Save and close button (run 38024495424).
@MainActor
private func findAccessibilityElement(_ label: String, in object: NSObject, labels: inout [String]) -> NSObject? {
  if object is WKWebView { return nil }
  if object.isAccessibilityElement, let own = object.accessibilityLabel {
    labels.append(own)
    if own == label { return object }
  }
  for child in object.accessibilityElements ?? [] {
    if let child = child as? NSObject, let match = findAccessibilityElement(label, in: child, labels: &labels) {
      return match
    }
  }
  if let view = object as? UIView {
    for subview in view.subviews {
      if let match = findAccessibilityElement(label, in: subview, labels: &labels) { return match }
    }
  }
  return nil
}
