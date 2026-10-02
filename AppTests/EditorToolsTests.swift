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

  func testEraserModesMapToTheSharedEngineABI() {
    XCTAssertEqual(EditorEraserMode.stroke.engineValue, INK_ERASER_STROKE)
    XCTAssertEqual(EditorEraserMode.partial.engineValue, INK_ERASER_FREE)
  }

  func testSelectorModesMapToTheSharedEngineABI() {
    XCTAssertEqual(EditorSelectorMode.freehand.engineValue, INK_SELECTOR_LASSO)
    XCTAssertEqual(EditorSelectorMode.rectangle.engineValue, INK_SELECTOR_RECT)
    XCTAssertEqual(EditorSelectorMode.oval.engineValue, INK_SELECTOR_OVAL)
    XCTAssertEqual(EditorSelectorMode.ruled.engineValue, INK_SELECTOR_RULED)
  }


  @MainActor
  func testPenLibraryRoundTripsTheEngineFormat() throws {
    let defaults = try EditorPenLibrary.defaultJSON()
    let library = try EditorPenLibrary(json: defaults)

    XCTAssertEqual(library.palette, [0x1A1A1A, 0x1F4FB5, 0xD92D39, 0x29955B, 0xFFCF26])
    XCTAssertTrue(library.saved.isEmpty)
    XCTAssertEqual(try library.json(), defaults)
  }
  @MainActor
  func testHistoryUsesTheSharedDocument() throws {
    let document = EngineDocument(seed: 11)
    XCTAssertEqual(try document.pageCount(), 1)

    try document.appendPage()
    XCTAssertEqual(try document.pageCount(), 2)

    let undo = try XCTUnwrap(document.undo())
    XCTAssertEqual(undo.page, 0)
    XCTAssertEqual(try document.pageCount(), 1)

    let redo = try XCTUnwrap(document.redo())
    XCTAssertEqual(redo.page, 1)
    XCTAssertEqual(try document.pageCount(), 2)
  }
}
