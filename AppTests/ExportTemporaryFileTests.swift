import Foundation
import XCTest
@testable import MathNotes

final class ExportTemporaryFileTests: XCTestCase {
  func testExportTemporaryFileCleanupIsIdempotent() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("pdf")
    try Data("%PDF-test".utf8).write(to: url, options: .atomic)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    removeExportTemporaryFile(url)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

    removeExportTemporaryFile(url)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }
}
