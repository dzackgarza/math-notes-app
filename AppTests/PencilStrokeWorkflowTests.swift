import Hammer
import InkEngine
import SwiftUI
import UIKit
import XCTest

@testable import MathNotes

// On the device small strokes vanished as the pencil lifted, larger ones at
// random, and erasing sometimes did nothing. This drives the editor pane the
// app shows for an open note with pencil events through UIKit's real event
// path (Hammer), lets the app's own autosave write the notebook, and counts the
// strokes in the page file it wrote.
@MainActor
final class PencilStrokeWorkflowTests: XCTestCase {
  private var window: UIWindow?
  private var directory: URL?

  override func tearDown() async throws {
    window?.isHidden = true
    window = nil
    if let directory { try FileManager.default.removeItem(at: directory) }
  }

  private struct OpenEditor {
    let events: EventGenerator
    let canvas: InkCanvasView
    let center: CGPoint
    let session: OpenNotebookSession
    let state: EditorWorkflowState
    let directory: URL
    let reference: NotebookReference
  }

  // A note created in a folder attached as the picker attaches it, open in the
  // editor pane, saved by the app's own autosave.
  private func openEditor(title: String) throws -> OpenEditor {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    let root = try NotesRootAccess(selectedURL: directory)
    let (reference, document) = try root.createNote(
      title: title,
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let session = OpenNotebookSession(reference: reference, document: document)
    let state = EditorWorkflowState()

    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(
      rootView: EditorWorkflowHost(session: session, state: state) {
        // ContentView.scheduleNotebookSave and saveSession, against this root.
        session.scheduleAutosave(
          checkpoint: { try root.checkpointRecovery(session.document, notebook: session.reference) }
        ) {
          do {
            try session.performSave { try root.save(session.document, notebook: session.reference) }
          } catch {
            XCTFail("autosave failed: \(error)")
          }
        }
      })
    window.makeKeyAndVisible()
    self.window = window

    let events = try EventGenerator(window: window)
    try events.waitUntilWindowIsReady()
    let canvas = try XCTUnwrap(firstSubview(of: InkCanvasView.self, in: window))
    return OpenEditor(
      events: events, canvas: canvas,
      center: canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil),
      session: session, state: state, directory: directory, reference: reference)
  }

  func testPencilStrokesAndStrokeEraseReachTheSavedPage() throws {
    let editor = try openEditor(title: "Pencil Workflow")
    let (events, center, session, state, directory, reference) =
      (editor.events, editor.center, editor.session, editor.state, editor.directory, editor.reference)

    // A short tick, the kind that vanished on lift.
    try events.stylusDown(at: center, azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    try events.stylusMove(to: CGPoint(x: center.x + 6, y: center.y + 4), duration: 0.05)
    try events.stylusUp()
    try awaitSaved(session)
    let tick = try savedStrokeIDs(directory, reference)
    XCTAssertEqual(tick.count, 1, "the short pencil stroke was not saved")

    // A long stroke across the page.
    let rowY = center.y + 80
    try events.stylusDown(at: CGPoint(x: center.x - 150, y: rowY), azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    try events.stylusMove(to: CGPoint(x: center.x + 150, y: rowY), duration: 0.5)
    try events.stylusUp()
    try awaitSaved(session)
    let both = try savedStrokeIDs(directory, reference)
    XCTAssertEqual(both.count, 2, "the long pencil stroke was not saved")
    XCTAssertTrue(tick.isSubset(of: both), "the long stroke replaced the tick")

    // The stroke eraser drawn across the long stroke removes it and only it.
    state.tool = .eraser
    try events.stylusDown(at: CGPoint(x: center.x, y: rowY - 40), azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    try events.stylusMove(to: CGPoint(x: center.x, y: rowY + 40), duration: 0.3)
    try events.stylusUp()
    try awaitSaved(session)
    XCTAssertEqual(try savedStrokeIDs(directory, reference), tick, "the stroke eraser must remove the long stroke and only it")
  }

  // The partial eraser (docs/specs/core-features.md, L1) drawn across the middle
  // of a stroke cuts it in two: the saved page holds two strokes in its place.
  func testThePartialEraserCutsAStrokeInTwo() throws {
    let editor = try openEditor(title: "Partial Erase Workflow")
    let rowY = editor.center.y + 40
    try editor.events.stylusDown(
      at: CGPoint(x: editor.center.x - 150, y: rowY), azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    try editor.events.stylusMove(to: CGPoint(x: editor.center.x + 150, y: rowY), duration: 0.5)
    try editor.events.stylusUp()
    try awaitSaved(editor.session)
    let whole = try savedStrokeIDs(editor.directory, editor.reference)
    XCTAssertEqual(whole.count, 1)

    editor.state.tool = .eraser
    editor.state.eraserMode = .partial
    try editor.events.stylusDown(
      at: CGPoint(x: editor.center.x, y: rowY - 40), azimuth: 0.8, altitude: 0.9, pressure: 0.5)
    try editor.events.stylusMove(to: CGPoint(x: editor.center.x, y: rowY + 40), duration: 0.3)
    try editor.events.stylusUp()
    try awaitSaved(editor.session)
    let pieces = try savedStrokeIDs(editor.directory, editor.reference)
    XCTAssertEqual(pieces.count, 2, "the partial eraser did not cut the stroke in two")
    XCTAssertTrue(pieces.isDisjoint(with: whole), "the cut stroke is still on the page whole")
  }

  // Finger drawing (docs/specs/core-features.md, L1): off, a finger drag moves
  // the page and leaves the document unchanged; on, it draws a stroke that
  // reaches the saved page.
  func testAFingerDrawsOnlyWhenFingerDrawingIsOn() throws {
    let editor = try openEditor(title: "Finger Workflow")
    let rowY = editor.center.y + 60
    let unsavedBefore = try editor.session.document.dirtyFiles()

    try editor.events.fingerDown(at: CGPoint(x: editor.center.x - 120, y: rowY))
    try editor.events.fingerMove(to: CGPoint(x: editor.center.x + 120, y: rowY), duration: 0.4)
    try editor.events.fingerUp()
    XCTAssertEqual(
      try editor.session.document.dirtyFiles(), unsavedBefore, "a finger drew with finger drawing off")

    editor.state.fingerDraws = true
    let adopted = expectation(for: NSPredicate { _, _ in editor.canvas.fingerDrawing }, evaluatedWith: nil)
    wait(for: [adopted], timeout: 5)
    try editor.events.fingerDown(at: CGPoint(x: editor.center.x - 120, y: rowY))
    try editor.events.fingerMove(to: CGPoint(x: editor.center.x + 120, y: rowY), duration: 0.4)
    try editor.events.fingerUp()
    try awaitSaved(editor.session)
    XCTAssertEqual(try savedStrokeIDs(editor.directory, editor.reference).count, 1, "the finger stroke was not saved")
  }

  // The app's autosave runs a second after the last edit; this waits for the
  // edit's save to finish, bounded so a save that never runs fails the test.
  private func awaitSaved(_ session: OpenNotebookSession) throws {
    let unsaved = expectation(for: NSPredicate { _, _ in session.saveStatus != .saved }, evaluatedWith: nil)
    wait(for: [unsaved], timeout: 5)
    let saved = expectation(for: NSPredicate { _, _ in session.saveStatus == .saved }, evaluatedWith: nil)
    wait(for: [saved], timeout: 5)
  }

  private func savedStrokeIDs(_ directory: URL, _ reference: NotebookReference) throws -> Set<String> {
    let page = directory.appendingPathComponent(reference.name, isDirectory: true)
      .appendingPathComponent("pages/0001.svg")
    let counter = SavedStrokeIDs()
    let parser = try XCTUnwrap(XMLParser(contentsOf: page))
    parser.delegate = counter
    XCTAssertTrue(parser.parse(), "the saved page is not well-formed: \(String(describing: parser.parserError))")
    return counter.strokes
  }

  private func firstSubview<T: UIView>(of type: T.Type, in view: UIView) -> T? {
    if let match = view as? T { return match }
    for subview in view.subviews {
      if let match = firstSubview(of: type, in: subview) { return match }
    }
    return nil
  }
}

// Each saved stroke is an element carrying its brush (mn:brush) and its id.
private final class SavedStrokeIDs: NSObject, XMLParserDelegate {
  var strokes: Set<String> = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?,
    attributes: [String: String]
  ) {
    guard attributes["mn:brush"] != nil else { return }
    guard let id = attributes["id"] else {
      parser.abortParsing()
      return
    }
    strokes.insert(id)
  }
}

@MainActor
@Observable
final class EditorWorkflowState {
  var penLibrary = EditorPenLibrary.defaults
  var tool: EditorTool = .pen
  var drawingTool: EditorTool = .pen
  var eraserMode: EditorEraserMode = .stroke
  var selectorMode: EditorSelectorMode = .freehand
  var spaceMode: EditorSpaceMode = .reflow
  var previousPencilTool: EditorTool?
  var fingerDraws = false
}

// The editor pane with ContentView's initial tool state for one open note.
private struct EditorWorkflowHost: View {
  let session: OpenNotebookSession
  @Bindable var state: EditorWorkflowState
  let onEditCommitted: () -> Void

  var body: some View {
    NotebookEditorPane(
      session: session,
      viewState: session.primaryView,
      active: true,
      focused: true,
      linked: false,
      linkedViewport: nil,
      arrangement: .vertical,
      fingerDraws: state.fingerDraws,
      hiddenTools: [],
      penLibrary: $state.penLibrary,
      tool: $state.tool,
      drawingTool: $state.drawingTool,
      eraserMode: $state.eraserMode,
      selectorMode: $state.selectorMode,
      spaceMode: $state.spaceMode,
      previousPencilTool: $state.previousPencilTool,
      onFocus: {},
      onViewportChanged: { _ in },
      onEditCommitted: onEditCommitted,
      onSaveRequested: {},
      onPensChanged: { _ in },
      onInsertImage: {},
      clippingsOpen: false,
      onShowClippings: {},
      onSaveClipping: { _ in },
      onLinkSelectionRequested: { _ in },
      onFollowLink: { _, _ in },
      onDropClipping: { _, _ in false },
      onEditFigure: { _ in },
      onError: { XCTFail("editor error: \($0)") })
  }
}
