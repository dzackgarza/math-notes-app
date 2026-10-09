import CoreGraphics
import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class ThumbnailCacheAcceptanceTests: XCTestCase {
  @MainActor
  func testThumbnailRendersAgainOnlyAfterFirstPageChanges() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cache = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.removeItem(at: cache)
    }

    var renders = 0
    let render: @MainActor (EngineDocument) throws -> Data = { document in
      renders += 1
      return try document.pagePNG(index: 0, width: 240)
    }
    let root = NotesRootAccess(
      testURL: directory, thumbnailCacheURL: cache, thumbnailRenderer: render)
    let (reference, _) = try root.createNote(
      title: "Counted thumbnail",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let loaded1 = try await root.thumbnail(reference)
    XCTAssertNotNil(loaded1)
    XCTAssertEqual(renders, 1)

    let relaunched = NotesRootAccess(
      testURL: directory, thumbnailCacheURL: cache, thumbnailRenderer: render)
    let loaded2 = try await relaunched.thumbnail(reference)
    XCTAssertNotNil(loaded2)
    XCTAssertEqual(renders, 1, "persistent cache hit must avoid a second render")

    let document = try await relaunched.load(reference)
    let canvas = InkCanvasView(document: document)
    canvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    canvas.layoutIfNeeded()
    canvas.setViewTransform(.identity)
    let page = try document.pageRect(index: 0)
    try canvas.editText(
      EngineTextProperties(content: "changed", width: 144, rtl: false),
      at: CGPoint(x: page.minX + 72, y: page.minY + 72),
      existing: false)
    try relaunched.save(document, notebook: reference)

    let loaded3 = try await relaunched.thumbnail(reference)
    XCTAssertNotNil(loaded3)
    XCTAssertEqual(renders, 2, "changing page 1 must render a new thumbnail")
  }
}
