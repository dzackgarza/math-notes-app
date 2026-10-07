import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class PageInsertionPersistenceTests: XCTestCase {
  @MainActor
  func testInsertedPageGetsNextFileWithoutRewritingExistingPages() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Three Pages",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    try document.appendPage()
    try document.appendPage()
    try root.save(document, notebook: reference)

    let noteDirectory = directory.appendingPathComponent(reference.name, isDirectory: true)
    let originalNames = ["0001.svg", "0002.svg", "0003.svg"]
    let originalPages = try Dictionary(uniqueKeysWithValues: originalNames.map { name in
      (name, try Data(contentsOf: noteDirectory.appendingPathComponent("pages/\(name)")))
    })

    try document.insertPage(at: 1)
    try root.save(document, notebook: reference)

    let indexData = try Data(contentsOf: noteDirectory.appendingPathComponent("notebook.json"))
    let index = try XCTUnwrap(JSONSerialization.jsonObject(with: indexData) as? [String: Any])
    let pages = try XCTUnwrap(index["pages"] as? [[String: Any]])
    XCTAssertEqual(
      pages.compactMap { $0["file"] as? String },
      ["pages/0001.svg", "pages/0004.svg", "pages/0002.svg", "pages/0003.svg"])

    for name in originalNames {
      let saved = try Data(contentsOf: noteDirectory.appendingPathComponent("pages/\(name)"))
      XCTAssertEqual(saved, originalPages[name], "inserting a page rewrote existing page \(name)")
    }
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: noteDirectory.appendingPathComponent("pages/0004.svg").path))
  }
}
