import Foundation
import XCTest
@testable import MathNotes

final class CrossHostNotebookCompatibilityTests: XCTestCase {
  @MainActor
  func testSharedFixtureKeepsExistingPagesByteIdenticalAfterIPadEdit() async throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixture = repository
      .appendingPathComponent("core/tests/fixtures/documents/full", isDirectory: true)
    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let noteDirectory = rootDirectory.appendingPathComponent("Shared Fixture", isDirectory: true)
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixture, to: noteDirectory)
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let pageNames = (1...5).map { String(format: "%04d.svg", $0) }
    let originalPages = try Dictionary(uniqueKeysWithValues: pageNames.map { name in
      let url = noteDirectory.appendingPathComponent("pages/\(name)")
      return (name, try Data(contentsOf: url))
    })

    let reference = NotebookReference(path: ["Shared Fixture"])
    let root = NotesRootAccess(testURL: rootDirectory)
    let document = try await root.load(reference)
    // 0005.svg is deliberately unlisted; all five files must survive unchanged.
    XCTAssertEqual(try document.pageCount(), 4)

    try document.appendPage()
    try root.save(document, notebook: reference)

    for name in pageNames {
      let saved = try Data(contentsOf: noteDirectory.appendingPathComponent("pages/\(name)"))
      XCTAssertEqual(saved, originalPages[name], "iPad save rewrote unaffected shared page \(name)")
    }
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: noteDirectory.appendingPathComponent("pages/0006.svg").path))

    let reopened = try await NotesRootAccess(testURL: rootDirectory).load(reference)
    XCTAssertEqual(try reopened.pageCount(), 5)
    XCTAssertTrue(try reopened.navigation().contains { $0.id == "b-bookmark0001" })
  }
}
