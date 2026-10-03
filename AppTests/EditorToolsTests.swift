import Foundation
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
    XCTAssertEqual(EditorEraserMode.ruled.engineValue, INK_ERASER_STROKE)
    XCTAssertNil(EditorEraserMode.stroke.selectorValue)
    XCTAssertNil(EditorEraserMode.partial.selectorValue)
    XCTAssertEqual(
      EditorEraserMode.ruled.selectorValue?.rawValue,
      INK_SELECTOR_RULED_ERASE.rawValue)
  }

  func testSelectorModesMapToTheSharedEngineABI() {
    XCTAssertEqual(EditorSelectorMode.freehand.engineValue, INK_SELECTOR_LASSO)
    XCTAssertEqual(EditorSelectorMode.rectangle.engineValue, INK_SELECTOR_RECT)
    XCTAssertEqual(EditorSelectorMode.oval.engineValue, INK_SELECTOR_OVAL)
    XCTAssertEqual(EditorSelectorMode.ruled.engineValue, INK_SELECTOR_RULED)
  }

  func testInsertSpaceModesMapToTheSharedEngineABI() {
    XCTAssertEqual(EditorSpaceMode.vertical.engineValue, INK_SELECTOR_SPACE_VERTICAL)
    XCTAssertEqual(EditorSpaceMode.horizontal.engineValue, INK_SELECTOR_SPACE_HORIZONTAL)
    XCTAssertEqual(EditorSpaceMode.reflow.engineValue, INK_SELECTOR_SPACE_RULED)
  }

  func testTextPropertiesMatchSharedJSONShape() throws {
    let properties = EngineTextProperties(
      content: "مرحبا\nText",
      width: 312.5,
      rtl: true)
    let data = try JSONEncoder().encode(properties)
    XCTAssertEqual(
      try JSONDecoder().decode(EngineTextProperties.self, from: data),
      properties)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(object["content"] as? String, "مرحبا\nText")
    XCTAssertEqual(object["width"] as? Double, 312.5)
    XCTAssertEqual(object["rtl"] as? Bool, true)
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
  func testEditedPenLibraryRoundTripsPalette() throws {
    var library = EditorPenLibrary.defaults
    library.palette = [0x102030, 0xA0B0C0]

    let decoded = try EditorPenLibrary(json: library.json())

    XCTAssertEqual(decoded.palette, [0x102030, 0xA0B0C0])
  }

  @MainActor
  func testPenLibraryColorAndSavedBrushOwnership() {
    var library = EditorPenLibrary.defaults
    let originalMarker = library.marker.rgb
    let originalHighlighter = library.highlighter.rgb

    library.setColor(0x2468AC, for: .pen)

    XCTAssertEqual(library.pen.rgb, 0x2468AC)
    XCTAssertEqual(library.marker.rgb, originalMarker)
    XCTAssertEqual(library.highlighter.rgb, originalHighlighter)
    XCTAssertEqual(library.drawingTool(for: library.pen), .pen)
    XCTAssertEqual(library.drawingTool(for: library.marker), .marker)
    XCTAssertEqual(library.drawingTool(for: library.highlighter), .highlighter)
  }

  @MainActor
  func testEditedPenLibraryRoundTripsSavedPreset() throws {
    var library = EditorPenLibrary.defaults
    var pen = library.pen
    pen.rgb = 0x2F6FEB
    pen.size = 2.4
    pen.opacity = 0.8
    library.setSettings(pen, for: .pen)
    library.saved.append(pen)

    let decoded = try EditorPenLibrary(json: library.json())

    XCTAssertEqual(decoded.pen.rgb, 0x2F6FEB)
    XCTAssertEqual(decoded.pen.size, 2.4)
    XCTAssertEqual(decoded.pen.opacity, 0.8)
    XCTAssertEqual(decoded.saved.count, 1)
    XCTAssertEqual(decoded.saved[0].rgb, 0x2F6FEB)
    XCTAssertEqual(decoded.saved[0].size, 2.4)
  }
  func testFollowLinksIsTransientAndNotToolbarCustomizable() {
    XCTAssertTrue(EditorTool.allCases.contains(.navigate))
    XCTAssertFalse(EditorTool.toolbarCases.contains(.navigate))
    XCTAssertEqual(
      Set(EditorTool.toolbarCases.map(\.rawValue)),
      Set(["pen", "marker", "highlighter", "eraser", "lasso", "text", "image", "space"]))
  }

  @MainActor
  func testDeletedPageCanBeRestoredByUndo() throws {
    let document = EngineDocument(seed: 13)
    try document.appendPage()
    XCTAssertEqual(try document.pageCount(), 2)

    try document.deletePage(at: 0)
    XCTAssertEqual(try document.pageCount(), 1)

    let undo = try XCTUnwrap(document.undo())
    XCTAssertGreaterThanOrEqual(undo.page, 0)
    XCTAssertEqual(try document.pageCount(), 2)
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
