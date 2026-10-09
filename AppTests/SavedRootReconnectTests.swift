import Foundation
import XCTest
@testable import MathNotes

final class SavedRootReconnectTests: XCTestCase {
  func testSavedRootURLResolvesPersistedBookmark() throws {
    NotesRootAccess.forgetSavedRoot()
    defer { NotesRootAccess.forgetSavedRoot() }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    try root.persistAsSavedRoot()

    XCTAssertTrue(NotesRootAccess.hasSavedRoot)
    XCTAssertEqual(
      NotesRootAccess.savedRootURL?.standardizedFileURL,
      directory.standardizedFileURL)
  }
}

// The saved folder was removed outside the app (Files, another device). The
// next launch must report why it cannot reconnect, not start as if no folder
// had ever been chosen.
final class RemovedSavedRootTests: XCTestCase {
  override func tearDown() {
    NotesRootAccess.forgetSavedRoot()
  }

  func testRestoringARemovedFolderFails() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try NotesRootAccess(selectedURL: directory).persistAsSavedRoot()
    try FileManager.default.removeItem(at: directory)

    XCTAssertThrowsError(try NotesRootAccess.restore()) { error in
      print("restoring a removed folder: \(error)")
    }
  }
}
