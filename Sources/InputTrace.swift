import ObjectiveC
import UIKit
import os

// Records every touch the app receives and every gesture recognizer state
// change in the app, through the two points all UIKit input passes:
// UIWindow.sendEvent and UIGestureRecognizer's state setter.
enum InputTrace {
  static let log = Logger(subsystem: "dev.zack.mathnotes", category: "input")

  static func install() {
    exchange(
      UIWindow.self,
      #selector(UIWindow.sendEvent(_:)),
      #selector(UIWindow.mathNotesTracedSendEvent(_:)))
    exchange(
      UIGestureRecognizer.self,
      NSSelectorFromString("setState:"),
      #selector(UIGestureRecognizer.mathNotesTracedSetState(_:)))
  }

  private static func exchange(_ type: AnyClass, _ original: Selector, _ traced: Selector) {
    guard let originalMethod = class_getInstanceMethod(type, original),
      let tracedMethod = class_getInstanceMethod(type, traced)
    else {
      fatalError("Input tracing cannot find \(original) on \(type)")
    }
    method_exchangeImplementations(originalMethod, tracedMethod)
  }

  static func describe(_ recognizer: UIGestureRecognizer) -> String {
    let view = recognizer.view.map { String(describing: type(of: $0)) } ?? "none"
    let name = recognizer.name.map { " name=\($0)" } ?? ""
    return "\(type(of: recognizer))@\(view) state=\(recognizer.state.rawValue) cancels=\(recognizer.cancelsTouchesInView) enabled=\(recognizer.isEnabled)\(name)"
  }
}

extension UIWindow {
  // After the exchange this runs as sendEvent, and the call below runs UIKit's.
  @objc func mathNotesTracedSendEvent(_ event: UIEvent) {
    if event.type == .touches, let touches = event.allTouches {
      for touch in touches {
        let point = touch.location(in: nil)
        let view = touch.view.map { String(describing: type(of: $0)) } ?? "none"
        let recognizers = (touch.gestureRecognizers ?? []).map(InputTrace.describe).joined(separator: "; ")
        InputTrace.log.info(
          "touch \(UInt(bitPattern: ObjectIdentifier(touch).hashValue), privacy: .public) type=\(touch.type.rawValue, privacy: .public) phase=\(touch.phase.rawValue, privacy: .public) x=\(Double(point.x), format: .fixed(precision: 1), privacy: .public) y=\(Double(point.y), format: .fixed(precision: 1), privacy: .public) force=\(Double(touch.force), format: .fixed(precision: 2), privacy: .public) view=\(view, privacy: .public) recognizers=[\(recognizers, privacy: .public)]")
      }
    }
    mathNotesTracedSendEvent(event)
  }
}

extension UIGestureRecognizer {
  // After the exchange this runs as the state setter, and the call below runs UIKit's.
  @objc func mathNotesTracedSetState(_ state: UIGestureRecognizer.State) {
    let previous = self.state
    mathNotesTracedSetState(state)
    guard previous != state else { return }
    InputTrace.log.info(
      "recognizer \(previous.rawValue, privacy: .public)->\(state.rawValue, privacy: .public) \(InputTrace.describe(self), privacy: .public)")
  }
}
