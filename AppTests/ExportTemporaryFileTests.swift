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

  func testExportWritesUniqueFilesWithExpectedContents() throws {
    let first = try writeTemporaryPDFExport(Data("first".utf8), name: "Notes")
    let second = try writeTemporaryPDFExport(Data("second".utf8), name: "Notes")
    defer {
      removeExportTemporaryFile(first)
      removeExportTemporaryFile(second)
    }
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
    XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
  }

  func testCleanupDoesNotRemoveUnrelatedPrefixedDirectory() throws {
    let container = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let unrelated = container.appendingPathComponent("mathnotes-export-unrelated", isDirectory: true)
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: container) }
    let url = unrelated.appendingPathComponent("example.pdf")
    let sentinel = unrelated.appendingPathComponent("sentinel")
    try Data("pdf".utf8).write(to: url)
    try Data("keep".utf8).write(to: sentinel)
    removeExportTemporaryFile(url)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
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
