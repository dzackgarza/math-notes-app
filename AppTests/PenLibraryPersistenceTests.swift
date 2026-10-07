import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class PenLibraryPersistenceTests: XCTestCase {
  @MainActor
  func testSharedPenFileSurvivesRootReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    var library = try root.penLibrary()

    var pen = library.pen
    pen.rgb = 0x2457A6
    pen.size = 2.75
    pen.opacity = 0.82
    library.setSettings(pen, for: .pen)

    var marker = library.marker
    marker.rgb = 0x8B4513
    marker.size = 4.5
    library.setSettings(marker, for: .marker)

    library.palette = [0x2457A6, 0x8B4513, 0xE7B416]
    library.saved = [pen, marker]
    try root.savePenLibrary(library)

    let reopened = try NotesRootAccess(testURL: directory).penLibrary()
    XCTAssertEqual(reopened.pen.rgb, pen.rgb)
    XCTAssertEqual(reopened.pen.size, pen.size)
    XCTAssertEqual(reopened.pen.opacity, pen.opacity)
    XCTAssertEqual(reopened.marker.rgb, marker.rgb)
    XCTAssertEqual(reopened.marker.size, marker.size)
    XCTAssertEqual(reopened.palette, library.palette)
    XCTAssertEqual(reopened.saved.count, 2)
    XCTAssertEqual(reopened.saved[0].brush, pen.brush)
    XCTAssertEqual(reopened.saved[0].rgb, pen.rgb)
    XCTAssertEqual(reopened.saved[0].size, pen.size)
    XCTAssertEqual(reopened.saved[1].brush, marker.brush)
    XCTAssertEqual(reopened.saved[1].rgb, marker.rgb)
    XCTAssertEqual(reopened.saved[1].size, marker.size)

    let bytes = try Data(contentsOf: directory.appendingPathComponent(".pens.json"))
    let text = String(decoding: bytes, as: UTF8.self)
    XCTAssertTrue(text.hasSuffix("\n"))
    XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"pen\"")?.lowerBound),
                      try XCTUnwrap(text.range(of: "\"marker\"")?.lowerBound))
    XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"marker\"")?.lowerBound),
                      try XCTUnwrap(text.range(of: "\"highlighter\"")?.lowerBound))
    XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"highlighter\"")?.lowerBound),
                      try XCTUnwrap(text.range(of: "\"palette\"")?.lowerBound))
    XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"palette\"")?.lowerBound),
                      try XCTUnwrap(text.range(of: "\"saved\"")?.lowerBound))
  }
}
