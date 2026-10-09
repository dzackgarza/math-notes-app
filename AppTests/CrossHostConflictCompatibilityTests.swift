import CoreGraphics
import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class CrossHostConflictCompatibilityTests: XCTestCase {
  @MainActor
  func testDropboxPageConflictKeepsBothVersionsAndClearsConflict() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Shared Dropbox Note",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let noteDirectory = directory.appendingPathComponent(reference.name, isDirectory: true)
    let pageDirectory = noteDirectory.appendingPathComponent("pages", isDirectory: true)
    let originalURL = pageDirectory.appendingPathComponent("0001.svg")
    let original = try Data(contentsOf: originalURL)

    let canvas = InkCanvasView(document: document)
    canvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    canvas.layoutIfNeeded()
    canvas.setViewTransform(.identity)
    try canvas.editText(
      EngineTextProperties(content: "Dropbox revision", width: 170, rtl: false),
      at: CGPoint(x: 90, y: 120), existing: false)
    let editedPage = try XCTUnwrap(document.dirtyFiles().first { $0.path == "pages/0001.svg" })
    guard case let .write(dropboxCopy) = editedPage.kind else {
      XCTFail("Editing text must produce a page write")
      return
    }
    let conflictURL = pageDirectory
      .appendingPathComponent("0001 (Zack's conflicted copy 2026-10-07).svg")
    try dropboxCopy.write(to: conflictURL, options: .atomic)

    let conflict = try XCTUnwrap(
      try root.conflicts(reference).first { $0.provider == "Dropbox" })
    XCTAssertEqual(conflict.original, "pages/0001.svg")
    XCTAssertTrue(conflict.page)

    try root.resolveConflict(reference, conflict: conflict, choice: .both)

    XCTAssertEqual(try root.conflictCount(reference), 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: conflictURL.path))
    let reopened = try await root.load(reference)
    XCTAssertEqual(try reopened.pageCount(), 2)

    let indexData = try Data(contentsOf: noteDirectory.appendingPathComponent("notebook.json"))
    let index = try XCTUnwrap(JSONSerialization.jsonObject(with: indexData) as? [String: Any])
    let pages = try XCTUnwrap(index["pages"] as? [[String: Any]])
    let pageBytes = try pages.map { entry -> Data in
      let path = try XCTUnwrap(entry["file"] as? String)
      let url = path.split(separator: "/").reduce(noteDirectory) { partial, component in
        partial.appendingPathComponent(String(component))
      }
      return try Data(contentsOf: url)
    }
    XCTAssertTrue(pageBytes.contains(original))
    let copiedPage = try XCTUnwrap(pageBytes.last)
    XCTAssertTrue(String(decoding: copiedPage, as: UTF8.self).contains("Dropbox revision"))
    XCTAssertFalse(String(decoding: original, as: UTF8.self).contains("Dropbox revision"))
    let verificationCanvas = InkCanvasView(document: reopened)
    verificationCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    verificationCanvas.layoutIfNeeded()
    verificationCanvas.setViewTransform(.identity)
    try verificationCanvas.selectAll(page: 1)
    let copiedContent = try XCTUnwrap(verificationCanvas.copySelection())
    XCTAssertTrue(copiedContent.contains("Dropbox revision"))
  }
}
