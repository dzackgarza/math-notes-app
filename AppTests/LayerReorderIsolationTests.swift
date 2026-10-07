import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class LayerReorderIsolationTests: XCTestCase {
  @MainActor
  func testLayerReorderChangesOnlyNotebookAndPageFiles() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Layer isolation",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.appendPage()
    try document.addLayer(name: "Annotations")
    try root.save(document, notebook: reference)

    let noteURL = directory.appendingPathComponent(reference.name, isDirectory: true)
    let before = try fileSnapshot(root: noteURL)
    let indexData = try Data(contentsOf: noteURL.appendingPathComponent("notebook.json"))
    let index = try XCTUnwrap(JSONSerialization.jsonObject(with: indexData) as? [String: Any])
    let pages = try XCTUnwrap(index["pages"] as? [[String: Any]])
    let pageFiles = Set(try pages.map { entry in
      try XCTUnwrap(entry["file"] as? String)
    })

    try document.moveLayer(from: 1, to: 0)
    try root.save(document, notebook: reference)

    let after = try fileSnapshot(root: noteURL)
    XCTAssertEqual(Set(before.keys), Set(after.keys))
    let changed = Set(before.keys.filter { before[$0] != after[$0] })
    XCTAssertEqual(changed, pageFiles.union(["notebook.json"]))
  }

  private func fileSnapshot(root: URL) throws -> [String: Data] {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    let files = try XCTUnwrap(
      FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles]))

    var snapshot: [String: Data] = [:]
    for case let url as URL in files {
      let values = try url.resourceValues(forKeys: Set(keys))
      guard values.isRegularFile == true else { continue }
      let relative = String(url.path.dropFirst(root.path.count + 1))
      snapshot[relative] = try Data(contentsOf: url)
    }
    return snapshot
  }
}
