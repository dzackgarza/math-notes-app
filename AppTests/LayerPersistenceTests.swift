import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class LayerPersistenceTests: XCTestCase {
  @MainActor
  func testLayerReorderPersistsInNotebookAndEveryPage() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Layer order",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.appendPage()
    try document.addLayer(name: "Annotations")

    let original = try document.layers()
    XCTAssertEqual(original.map(\.name), ["Ink", "Annotations"])
    let inkID = original[0].id
    let annotationsID = original[1].id

    try document.moveLayer(from: 1, to: 0)
    try root.save(document, notebook: reference)

    let reopened = try await NotesRootAccess(testURL: directory).load(reference)
    XCTAssertEqual(try reopened.layers().map(\.id), [annotationsID, inkID])

    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let notebookData = try Data(contentsOf: noteURL.appendingPathComponent("notebook.json"))
    let notebook = try XCTUnwrap(
      JSONSerialization.jsonObject(with: notebookData) as? [String: Any])
    let layers = try XCTUnwrap(notebook["layers"] as? [[String: Any]])
    XCTAssertEqual(layers.compactMap { $0["id"] as? String }, [annotationsID, inkID])

    let pageEntries = try XCTUnwrap(notebook["pages"] as? [[String: Any]])
    XCTAssertEqual(pageEntries.count, 2)
    for entry in pageEntries {
      let file = try XCTUnwrap(entry["file"] as? String)
      let pageURL = file.split(separator: "/").reduce(noteURL) { partial, component in
        partial.appendingPathComponent(String(component))
      }
      let svg = try String(contentsOf: pageURL, encoding: .utf8)
      let annotations = try XCTUnwrap(svg.range(of: "id=\"\(annotationsID)\""))
      let ink = try XCTUnwrap(svg.range(of: "id=\"\(inkID)\""))
      XCTAssertLessThan(annotations.lowerBound, ink.lowerBound)
    }
  }
}
