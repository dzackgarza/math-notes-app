import CoreGraphics
import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class CrossNotebookLinkPersistenceTests: XCTestCase {
  @MainActor
  func testCrossNotebookBookmarkLinkSurvivesIPadSaveAndReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let sourceFolder = try root.createFolder(parent: FolderReference(path: []), name: "Seminar")
    let targetFolder = try root.createFolder(parent: FolderReference(path: []), name: "References")
    let (sourceReference, source) = try root.createNote(
      title: "Day 1",
      parent: sourceFolder,
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let (targetReference, target) = try root.createNote(
      title: "K3 notes",
      parent: targetFolder,
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)

    let targetCanvas = InkCanvasView(document: target)
    targetCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    targetCanvas.layoutIfNeeded()
    targetCanvas.setViewTransform(.identity)
    try targetCanvas.editText(
      EngineTextProperties(content: "Period map", width: 160, rtl: false),
      at: CGPoint(x: 100, y: 120),
      existing: false)
    XCTAssertTrue(try targetCanvas.selectText(at: CGPoint(x: 108, y: 128)))
    try targetCanvas.bookmarkSelection()
    let bookmark = try XCTUnwrap(
      target.navigation().first { !$0.id.isEmpty && $0.href.isEmpty })
    let sourcePage = try XCTUnwrap(
      source.navigation().first { $0.id.isEmpty && $0.href.isEmpty })
    let href = try NotebookLink.href(
      source: sourceReference,
      sourceFile: sourcePage.file,
      target: targetReference,
      mark: bookmark)

    let sourceCanvas = InkCanvasView(document: source)
    sourceCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    sourceCanvas.layoutIfNeeded()
    sourceCanvas.setViewTransform(.identity)
    try sourceCanvas.editText(
      EngineTextProperties(content: "See period map", width: 180, rtl: false),
      at: CGPoint(x: 100, y: 220),
      existing: false)
    XCTAssertTrue(try sourceCanvas.selectText(at: CGPoint(x: 108, y: 228)))
    try sourceCanvas.linkSelection(href)

    try root.save(target, notebook: targetReference)
    try root.save(source, notebook: sourceReference)

    let reopenedRoot = NotesRootAccess(testURL: directory)
    let reopenedSource = try await reopenedRoot.load(sourceReference)
    let persistedLink = try XCTUnwrap(
      reopenedSource.navigation().first { !$0.href.isEmpty })
    XCTAssertEqual(persistedLink.href, href)

    let resolved = try NotebookLink.resolve(
      source: sourceReference,
      sourceFile: persistedLink.file,
      href: persistedLink.href)
    XCTAssertEqual(
      resolved,
      .page(reference: targetReference, file: bookmark.file, id: bookmark.id))
    let loaded1 = try await reopenedRoot.load(targetReference)
    XCTAssertTrue(try loaded1.navigation().contains { $0.id == bookmark.id })
  }
}
