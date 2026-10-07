import XCTest
@testable import MathNotes

final class FilePresenterLifecycleTests: XCTestCase {
  @MainActor
  func testRootPresenterSuspendsAndResumesIdempotently() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    XCTAssertTrue(root.filePresentationRegisteredForTesting)

    root.suspendFilePresentation()
    XCTAssertFalse(root.filePresentationRegisteredForTesting)
    root.suspendFilePresentation()
    XCTAssertFalse(root.filePresentationRegisteredForTesting)

    root.resumeFilePresentation()
    XCTAssertTrue(root.filePresentationRegisteredForTesting)
    root.resumeFilePresentation()
    XCTAssertTrue(root.filePresentationRegisteredForTesting)
  }
}
