import Foundation
import InkEngine
import XCTest
@testable import MathNotes

// Choosing a notes folder and browsing it must leave the folder unchanged:
// on the iPad, attaching a Dropbox folder wrote eight template notebooks and
// .pens.json into it. Files are created only by an action that needs them.
final class ReadOnlyAttachTests: XCTestCase {
  @MainActor
  func testAttachingAndBrowsingAFolderWritesNothing() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let notes = directory.appendingPathComponent("Dropbox Notes", isDirectory: true)
    try FileManager.default.createDirectory(
      at: notes.appendingPathComponent("Lecture notes", isDirectory: true),
      withIntermediateDirectories: true)
    try Data("unrelated\n".utf8).write(to: notes.appendingPathComponent("todo.txt"))
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = try tree(notes)

    // The reads ContentView makes when a folder is attached and the library,
    // pen toolbar, and new-note sheet are shown.
    let root = NotesRootAccess(
      testURL: notes,
      recoveryURL: directory.appendingPathComponent("recovery", isDirectory: true),
      thumbnailCacheURL: directory.appendingPathComponent("thumbnails", isDirectory: true))
    _ = try root.penLibrary()
    _ = try await root.library(in: FolderReference(path: []), overview: true, sort: .name, direction: .ascending)
    let templates = try root.templateNames()
    XCTAssertTrue(templates.contains("blank"))
    _ = try root.paperPreview(template: "blank", pageSize: INK_PAGE_A4, orientation: INK_PORTRAIT)

    XCTAssertEqual(try tree(notes), before, "attaching and browsing changed the notes folder")
  }

  @MainActor
  func testCreatingANoteWritesOnlyTheTemplateItUses() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    _ = try root.createNote(
      title: "Lecture",
      parent: FolderReference(path: []),
      template: "grid-fine",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let templates = try FileManager.default.contentsOfDirectory(
      atPath: directory.appendingPathComponent(".templates").path)
    XCTAssertEqual(templates, ["grid-fine"])
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: directory.appendingPathComponent(".pens.json").path))
  }

  private func tree(_ root: URL) throws -> [String: Data] {
    var files: [String: Data] = [:]
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]))
    for case let url as URL in enumerator {
      let relative = String(url.path.dropFirst(root.path.count))
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
      files[relative] = values.isRegularFile == true ? try Data(contentsOf: url) : Data()
    }
    return files
  }
}
