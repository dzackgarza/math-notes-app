import Foundation
import XCTest
@testable import MathNotes

final class ExportTemporaryFileTests: XCTestCase {
  func testConcurrentExportsHaveDistinctPathsAndRetainPDFNames() throws {
    let first = try temporaryPDFExportURL(name: "Same/Title")
    let second = try temporaryPDFExportURL(name: "Same/Title")
    defer {
      removeExportTemporaryFile(first)
      removeExportTemporaryFile(second)
    }
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(first.lastPathComponent, "Same-Title.pdf")
    XCTAssertEqual(second.lastPathComponent, "Same-Title.pdf")
    try Data("one".utf8).write(to: first)
    try Data("two".utf8).write(to: second)
    removeExportTemporaryFile(first)
    XCTAssertFalse(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
    XCTAssertEqual(try Data(contentsOf: second), Data("two".utf8))
  }

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
