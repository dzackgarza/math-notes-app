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
