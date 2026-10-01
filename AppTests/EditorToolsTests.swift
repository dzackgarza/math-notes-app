import InkEngine
import XCTest
@testable import MathNotes

final class EditorToolsTests: XCTestCase {
  @MainActor
  func testNativeRailReadsTheCoreDefaultPenFile() {
    let pens = EditorPenSet.defaults

    XCTAssertEqual(pens.pen.brush, UInt32(INK_BRUSH_PRESSURE_PEN.rawValue))
    XCTAssertEqual(pens.pen.rgb, 0x1A1A1A)
    XCTAssertEqual(pens.pen.size, 1.2)
    XCTAssertEqual(pens.pen.opacity, 1)

    XCTAssertEqual(pens.marker.brush, UInt32(INK_BRUSH_MARKER.rawValue))
    XCTAssertEqual(pens.marker.rgb, 0x1A1A1A)
    XCTAssertEqual(pens.marker.size, 1.2)
    XCTAssertEqual(pens.marker.opacity, 1)

    XCTAssertEqual(pens.highlighter.brush, UInt32(INK_BRUSH_HIGHLIGHTER.rawValue))
    XCTAssertEqual(pens.highlighter.rgb, 0xFFE066)
    XCTAssertEqual(pens.highlighter.size, 9.6)
    XCTAssertEqual(pens.highlighter.opacity, 0.35)
  }

  @MainActor
  func testHistoryUsesTheSharedDocument() throws {
    let document = EngineDocument(seed: 11)
    XCTAssertEqual(try document.pageCount(), 1)

    try document.appendPage()
    XCTAssertEqual(try document.pageCount(), 2)

    XCTAssertTrue(try document.undo())
    XCTAssertEqual(try document.pageCount(), 1)

    XCTAssertTrue(try document.redo())
    XCTAssertEqual(try document.pageCount(), 2)
  }
}
