import UIKit
import XCTest

// SwiftUI controls are accessibility elements, not views: the tests find them
// by label in the window's accessibility tree, as VoiceOver does, and touch
// them through UIKit with Hammer.
@MainActor
extension XCTestCase {
  // The center, in screen coordinates, of the element with this label once it
  // exists (and, when asked, is enabled). Fails listing every label it saw.
  func center(ofAccessibilityElement label: String, enabled: Bool = false, in window: UIWindow) throws -> CGPoint {
    var labels: [String] = []
    let found = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        labels = []
        guard let element = accessibilityElement(label, in: window, labels: &labels) else { return false }
        return !enabled || !element.accessibilityTraits.contains(.notEnabled)
      },
      object: nil)
    let result = XCTWaiter().wait(for: [found], timeout: 20)
    labels = []
    let element = try XCTUnwrap(
      accessibilityElement(label, in: window, labels: &labels),
      "no accessibility element \"\(label)\" (\(result)); labels found: \(labels)")
    XCTAssertEqual(result, .completed, "\"\(label)\" never became \(enabled ? "enabled" : "present")")
    let frame = element.accessibilityFrame
    return CGPoint(x: frame.midX, y: frame.midY)
  }
}

@MainActor
private func accessibilityElement(_ label: String, in object: NSObject, labels: inout [String]) -> NSObject? {
  if object.isAccessibilityElement, let own = object.accessibilityLabel {
    labels.append(own)
    if own == label { return object }
  }
  for child in object.accessibilityElements ?? [] {
    if let child = child as? NSObject, let match = accessibilityElement(label, in: child, labels: &labels) {
      return match
    }
  }
  if let view = object as? UIView {
    for subview in view.subviews {
      if let match = accessibilityElement(label, in: subview, labels: &labels) { return match }
    }
  }
  return nil
}
