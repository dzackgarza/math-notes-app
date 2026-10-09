import Hammer
import SwiftUI
import UIKit
import XCTest

@testable import MathNotes

// On the device the figure sheet stayed on "Loading figure editor…". This
// hosts the sheet as ContentView presents it, waits until its "Save and close"
// is enabled (the editor answered the sheet's load with 'loaded'), taps it
// through UIKit, and requires the editor to hand back the figure's source as a
// persistent draft.
@MainActor
final class FigureEditorSheetWorkflowTests: XCTestCase {
  private var window: UIWindow?

  override func tearDown() async throws {
    window?.isHidden = true
    window = nil
  }

  func testSaveAndCloseReturnsTheFigureSourceAsAPersistentDraft() throws {
    let source = "\\begin{tikzpicture}\n\\draw (0,0) rectangle (2,1);\n\\draw (0,0) -- (2,1);\n\\end{tikzpicture}\n"
    let saved = expectation(description: "the sheet saved a persistent draft")
    var persistentDrafts: [String] = []
    let sheet = FigureEditorSheet(
      request: FigureEditorRequest(id: "figure-workflow", source: source, viewID: UUID()),
      onDraft: { text, persistent in
        guard persistent else { return }
        persistentDrafts.append(text)
        if persistentDrafts.count == 1 { saved.fulfill() }
      },
      onDismiss: {})

    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(rootView: sheet)
    window.makeKeyAndVisible()
    self.window = window
    let events = try EventGenerator(window: window)
    try events.waitUntilWindowIsReady()

    let limit = TimeInterval(FigureEditorPage.startLimit.components.seconds)
    let enabled = expectation(
      for: NSPredicate { _, _ in self.saveButton(in: window).map { !$0.accessibilityTraits.contains(.notEnabled) } ?? false },
      evaluatedWith: nil)
    wait(for: [enabled], timeout: limit)
    let button = try XCTUnwrap(
      saveButton(in: window),
      "no Save and close control; labelled views: \(labels(in: window))")
    try events.fingerTap(at: button)

    wait(for: [saved], timeout: limit)
    XCTAssertEqual(Set(persistentDrafts), [source], "a persistent draft differs from the figure's source")
  }

  private func saveButton(in view: UIView) -> UIView? {
    if view.accessibilityIdentifier == "figure-editor-save" || view.accessibilityLabel == "Save and close" {
      return view
    }
    for subview in view.subviews {
      if let match = saveButton(in: subview) { return match }
    }
    return nil
  }

  private func labels(in view: UIView) -> [String] {
    [view.accessibilityIdentifier, view.accessibilityLabel].compactMap { $0 }
      + view.subviews.flatMap(labels(in:))
  }
}
