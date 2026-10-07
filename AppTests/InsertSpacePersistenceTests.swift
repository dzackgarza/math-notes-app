import CoreGraphics
import Foundation
import InkEngine
import Metal
import QuartzCore
import XCTest
@testable import MathNotes

final class InsertSpacePersistenceTests: XCTestCase {
  @MainActor
  func testVerticalInsertSpaceOverflowSurvivesIPadSaveAndReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (reference, document) = try root.createNote(
      title: "Insert Space Persistence",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let queue = try XCTUnwrap(device.makeCommandQueue())
    let layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.drawableSize = CGSize(width: 1200, height: 2000)

    var canvas: OpaquePointer?
    XCTAssertEqual(
      ink_canvas_create_metal(
        document.pointer,
        Unmanaged.passUnretained(device).toOpaque(),
        Unmanaged.passUnretained(queue).toOpaque(),
        Unmanaged.passUnretained(layer).toOpaque(),
        &canvas),
      INK_OK)
    let engineCanvas = try XCTUnwrap(canvas)
    defer { ink_canvas_free(engineCanvas) }
    XCTAssertEqual(ink_canvas_set_surface_size(engineCanvas, 1200, 2000, 1), INK_OK)
    XCTAssertEqual(ink_canvas_set_view(engineCanvas, 1, 0, 0, 1, 0, 0), INK_OK)

    var marker = EditorPenSet.defaults.marker
    XCTAssertEqual(ink_canvas_set_tool(engineCanvas, &marker), INK_OK)
    let page = try document.pageRect(index: 0)
    try sendDrag(
      canvas: engineCanvas,
      from: CGPoint(x: page.minX + 100, y: page.minY + 800),
      to: CGPoint(x: page.minX + 220, y: page.minY + 800),
      startTime: 1_000)

    XCTAssertEqual(
      ink_canvas_set_selector(engineCanvas, INK_SELECTOR_SPACE_VERTICAL, 1),
      INK_OK)
    try sendDrag(
      canvas: engineCanvas,
      from: CGPoint(x: page.minX + 300, y: page.minY + 700),
      to: CGPoint(x: page.minX + 300, y: page.minY + 820),
      startTime: 2_000)

    XCTAssertEqual(try document.pageCount(), 2)
    try root.save(document, notebook: reference)

    let reopened = try NotesRootAccess(testURL: directory).load(reference)
    XCTAssertEqual(try reopened.pageCount(), 2)
    let reopenedCanvas = InkCanvasView(document: reopened)
    reopenedCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1600)
    reopenedCanvas.layoutIfNeeded()
    reopenedCanvas.setViewTransform(.identity)
    try reopenedCanvas.selectAll(page: 1)
    let movedInk = try XCTUnwrap(reopenedCanvas.copySelection())
    XCTAssertTrue(movedInk.contains("mn:brush"), "overflowed ink must remain editable after reopen")
  }

  private func sendDrag(
    canvas: OpaquePointer,
    from: CGPoint,
    to: CGPoint,
    startTime: Double
  ) throws {
    let distance = hypot(to.x - from.x, to.y - from.y)
    let steps = max(2, Int(ceil(distance / 10)))
    for index in 0...steps {
      let fraction = Double(index) / Double(steps)
      var sample = InkPenSample()
      sample.x = from.x + (to.x - from.x) * fraction
      sample.y = from.y + (to.y - from.y) * fraction
      sample.time = startTime + Double(index) * 10
      sample.pressure = 0.5
      sample.id = UInt32(index + 1)
      sample.tool = UInt8(INK_TOOL_PEN.rawValue)
      sample.phase = UInt8((index == 0
        ? INK_PHASE_BEGIN
        : index == steps ? INK_PHASE_END : INK_PHASE_MOVE).rawValue)
      XCTAssertEqual(ink_input(canvas, &sample, 1), INK_OK)
    }
  }
}
