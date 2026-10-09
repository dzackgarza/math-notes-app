import UIKit
import WebKit
import XCTest
@testable import MathNotes

// On the device the figure editor sheet loaded its page but never received the
// editor's 'init' message, so it showed "Loading figure editor…" until the app
// was force-quit. This loads the bundled editor exactly as the sheet does, in a
// visible window, and requires its 'init' message, reporting every page error.
@MainActor
final class FigureEditorStartupTests: XCTestCase {
  func testBundledFigureEditorStartsAndAnnouncesInit() throws {
    let recorder = FigureEditorRecorder()
    let webView = try FigureEditorPage.makeWebView(handler: recorder)
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 800, height: 800)
    let controller = UIViewController()
    controller.view = webView
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // The editor announces itself within half a second of loading in WebKit;
    // the bound allows for the first WebContent process launch on a cold simulator.
    wait(for: [recorder.initReceived], timeout: 5)
    XCTAssertEqual(
      recorder.events.first, "init",
      "the editor's first message was not 'init'; page reports: \(recorder.pageReports)")
  }
}

@MainActor
final class FigureEditorRecorder: NSObject, WKScriptMessageHandler {
  let initReceived = XCTestExpectation(description: "the editor sent 'init'")
  private(set) var events: [String] = []
  private(set) var pageReports: [String] = []

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard let body = message.body as? String else {
      pageReports.append("non-string message on \(message.name)")
      return
    }
    if message.name == "mathNotesFigureLog" {
      pageReports.append(body)
      return
    }
    guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
      let event = object["event"] as? String
    else {
      pageReports.append("message without an event: \(body)")
      return
    }
    events.append(event)
    if event == "init" { initReceived.fulfill() }
  }
}
