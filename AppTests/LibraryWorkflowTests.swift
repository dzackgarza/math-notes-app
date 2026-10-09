import Hammer
import InkEngine
import SwiftUI
import UIKit
import XCTest

@testable import MathNotes

// The app as it starts with a saved notes folder: ContentView restores the
// folder from its bookmark, the library lists it, and a note opened from the
// library takes pencil strokes that the app's autosave writes to the folder.
// On the device this path hung at launch and on opening a note.
@MainActor
final class LibraryWorkflowTests: XCTestCase {
  private var window: UIWindow?
  private var directory: URL?

  override func tearDown() async throws {
    window?.isHidden = true
    window = nil
    NotesRootAccess.forgetSavedRoot()
    if let directory { try FileManager.default.removeItem(at: directory) }
  }

  func testASavedFolderRelaunchesIntoTheLibraryAndANoteOpenedThereTakesPencilStrokes() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    // The folder as an earlier session left it: attached through the picker's
    // path, with a notebook holding one note, and saved for the next launch.
    let earlier = try NotesRootAccess(selectedURL: directory)
    let course = try earlier.createFolder(parent: FolderReference(path: []), name: "Course")
    _ = try earlier.createNote(
      title: "Lecture", parent: course, template: "blank", pageSize: INK_PAGE_A4, orientation: INK_PORTRAIT)
    try earlier.persistAsSavedRoot()

    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(
      rootView: ContentView().environmentObject(MathNotesSceneDelegate()))
    window.makeKeyAndVisible()
    self.window = window
    let events = try EventGenerator(window: window)
    try events.waitUntilWindowIsReady()

    try events.fingerTap(at: try center(of: "Open Course", in: window))
    try events.fingerTap(at: try center(of: "Open Lecture", in: window))
    let opened = expectation(
      for: NSPredicate { _, _ in self.firstSubview(of: InkCanvasView.self, in: window)?.window != nil },
      evaluatedWith: nil)
    wait(for: [opened], timeout: 10)
    let canvas = try XCTUnwrap(firstSubview(of: InkCanvasView.self, in: window))
    let center = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)

    try events.stylusDown(at: CGPoint(x: center.x - 120, y: center.y), azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    try events.stylusMove(to: CGPoint(x: center.x + 120, y: center.y), duration: 0.4)
    try events.stylusUp()

    // Saves replace the page file atomically, so every read parses.
    let page = directory.appendingPathComponent("Course/Lecture/pages/0001.svg")
    let saved = expectation(
      for: NSPredicate { _, _ in try! self.strokeCount(page) == 1 },
      evaluatedWith: nil)
    wait(for: [saved], timeout: 10)
  }

  // The center, in window coordinates, of the accessibility element with this
  // label; SwiftUI buttons are accessibility elements, not views.
  private func center(of label: String, in window: UIWindow) throws -> CGPoint {
    var labels: [String] = []
    let found = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        labels = []
        return self.accessibilityFrame(label, in: window, labels: &labels) != nil
      },
      object: nil)
    let result = XCTWaiter().wait(for: [found], timeout: 10)
    labels = []
    let frame = try XCTUnwrap(
      accessibilityFrame(label, in: window, labels: &labels),
      "no accessibility element \"\(label)\" (\(result)); labels found: \(labels)")
    // accessibilityFrame is in screen coordinates; the test window fills the screen.
    return CGPoint(x: frame.midX, y: frame.midY)
  }

  private func accessibilityFrame(_ label: String, in object: NSObject, labels: inout [String]) -> CGRect? {
    if object.isAccessibilityElement, let own = object.accessibilityLabel {
      labels.append(own)
      if own == label { return object.accessibilityFrame }
    }
    for child in object.accessibilityElements ?? [] {
      if let child = child as? NSObject, let frame = accessibilityFrame(label, in: child, labels: &labels) {
        return frame
      }
    }
    if let view = object as? UIView {
      for subview in view.subviews {
        if let frame = accessibilityFrame(label, in: subview, labels: &labels) { return frame }
      }
    }
    return nil
  }

  // Strokes in a page file: elements carrying a brush (mn:brush).
  private func strokeCount(_ page: URL) throws -> Int {
    let counter = BrushCounter()
    let parser = try XCTUnwrap(XMLParser(contentsOf: page))
    parser.delegate = counter
    guard parser.parse() else { throw try XCTUnwrap(parser.parserError) }
    return counter.count
  }

  private func firstSubview<T: UIView>(of type: T.Type, in view: UIView) -> T? {
    if let match = view as? T { return match }
    for subview in view.subviews {
      if let match = firstSubview(of: type, in: subview) { return match }
    }
    return nil
  }
}

private final class BrushCounter: NSObject, XMLParserDelegate {
  var count = 0

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if attributes["mn:brush"] != nil { count += 1 }
  }
}
