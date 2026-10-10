import Hammer
import InkEngine
import OSLog
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

    try events.fingerTap(at: try center(ofAccessibilityElement: "Open Course", in: window))
    try events.fingerTap(at: try center(ofAccessibilityElement: "Open Lecture", in: window))
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

  // Device capture 2026-10-09 23:29:00.865: with a lasso selection on the
  // page, a tap on Pen logged SwiftUI's "Modifying state during view update,
  // this will cause undefined behavior." twice. The same taps here, in the
  // app's own ContentView, through UIKit; the process's log must hold no
  // such fault, nor the editor's own fault naming the callback.
  func testATapOnPenWithALassoSelectionModifiesNoStateDuringAViewUpdate() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
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
    try events.fingerTap(at: try center(ofAccessibilityElement: "Open Course", in: window))
    try events.fingerTap(at: try center(ofAccessibilityElement: "Open Lecture", in: window))
    let opened = expectation(
      for: NSPredicate { _, _ in self.firstSubview(of: InkCanvasView.self, in: window)?.window != nil },
      evaluatedWith: nil)
    wait(for: [opened], timeout: 10)
    let canvas = try XCTUnwrap(firstSubview(of: InkCanvasView.self, in: window))
    let center = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
    try events.stylusDown(at: CGPoint(x: center.x - 120, y: center.y), azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    try events.stylusMove(to: CGPoint(x: center.x + 120, y: center.y), duration: 0.4)
    try events.stylusUp()

    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let start = store.position(date: Date())
    try events.fingerTap(at: try self.center(ofAccessibilityElement: "Lasso, Freehand", in: window))
    let corners = [
      CGPoint(x: center.x - 160, y: center.y - 50), CGPoint(x: center.x + 160, y: center.y - 50),
      CGPoint(x: center.x + 160, y: center.y + 50), CGPoint(x: center.x - 160, y: center.y + 50),
      CGPoint(x: center.x - 160, y: center.y - 50),
    ]
    try events.stylusDown(at: corners[0], azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    for corner in corners.dropFirst() { try events.stylusMove(to: corner, duration: 0.15) }
    try events.stylusUp()
    try events.fingerTap(at: try self.center(ofAccessibilityElement: "Pen", in: window))
    // The tap's view update has run once the canvas has the pen again.
    let messages = { try store.getEntries(at: start).compactMap { $0 as? OSLogEntryLog }.map(\.composedMessage) }
    let pen = expectation(
      for: NSPredicate { _, _ in try! messages().contains("tool pen eraser=stroke") }, evaluatedWith: nil)
    wait(for: [pen], timeout: 10)

    let logged = try messages()
    XCTAssertTrue(logged.contains("tool lasso eraser=stroke"), "the log store does not hold the app's own entries")
    XCTAssertEqual(
      logged.filter { $0.contains("Modifying state during view update") || $0.contains("during the editor's view update") },
      [])
  }

  // Hiding the active layer in the Layers sheet must not lose the next stroke:
  // it lands on a layer that is still visible and editable, and nothing is
  // written into the hidden one.
  func testAStrokeAfterHidingALayerLandsOnAVisibleLayer() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    let earlier = try NotesRootAccess(selectedURL: directory)
    let course = try earlier.createFolder(parent: FolderReference(path: []), name: "Course")
    let (lecture, document) = try earlier.createNote(
      title: "Lecture", parent: course, template: "blank", pageSize: INK_PAGE_A4, orientation: INK_PORTRAIT)
    try document.addLayer(name: "Sketch")
    try earlier.save(document, notebook: lecture)
    let layers = try document.layers()
    let (hidden, visible) = (layers[0], layers[1])
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

    try events.fingerTap(at: try center(ofAccessibilityElement: "Open Course", in: window))
    try events.fingerTap(at: try center(ofAccessibilityElement: "Open Lecture", in: window))
    try events.fingerTap(at: try center(ofAccessibilityElement: "Pages", in: window))
    try events.fingerTap(at: try center(ofAccessibilityElement: "Layers", in: window))
    try events.fingerTap(at: try center(ofAccessibilityElement: "Hide \(hidden.name)", in: window))
    try events.fingerTap(at: try center(ofAccessibilityElement: "Done", in: window))

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
      for: NSPredicate { _, _ in try! self.strokesByLayer(page, layers: layers)[visible.id] == 1 },
      evaluatedWith: nil)
    wait(for: [saved], timeout: 10)
    XCTAssertNil(try strokesByLayer(page, layers: layers)[hidden.id], "a stroke was written into the hidden layer")
  }

  // Strokes per layer in a page file: each layer is a <g> with the layer's id.
  private func strokesByLayer(_ page: URL, layers: [EngineLayer]) throws -> [String: Int] {
    let counter = LayerStrokeCounter(layerIDs: Set(layers.map(\.id)))
    let parser = try XCTUnwrap(XMLParser(contentsOf: page))
    parser.delegate = counter
    guard parser.parse() else { throw try XCTUnwrap(parser.parserError) }
    return counter.counts
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

// Counts brush elements (strokes) under each <g> whose id names a layer.
private final class LayerStrokeCounter: NSObject, XMLParserDelegate {
  let layerIDs: Set<String>
  var counts: [String: Int] = [:]
  private var groups: [String?] = []

  init(layerIDs: Set<String>) {
    self.layerIDs = layerIDs
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if elementName == "g" { groups.append(attributes["id"]) }
    if attributes["mn:brush"] != nil, let layer = groups.compactMap({ $0 }).last(where: layerIDs.contains) {
      counts[layer, default: 0] += 1
    }
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
    if elementName == "g" { groups.removeLast() }
  }
}
