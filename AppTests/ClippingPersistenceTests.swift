import CoreGraphics
import Foundation
import InkEngine
import XCTest
@testable import MathNotes

final class ClippingPersistenceTests: XCTestCase {
  @MainActor
  func testSavedSelectionClippingSurvivesRootReopenAndPastesWithFreshIdentity() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let (_, source) = try root.createNote(
      title: "Clipping Source",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let sourceCanvas = InkCanvasView(document: source)
    sourceCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    sourceCanvas.layoutIfNeeded()
    sourceCanvas.setViewTransform(.identity)
    try sourceCanvas.editText(
      EngineTextProperties(content: "Reusable lemma", width: 170, rtl: false),
      at: CGPoint(x: 90, y: 120),
      existing: false)
    try sourceCanvas.selectAll(page: 0)
    let selection = try XCTUnwrap(sourceCanvas.copySelection())
    let sourceIDs = elementIDs(in: selection)
    XCTAssertFalse(sourceIDs.isEmpty)

    try root.addClipping(svg: selection)
    let previews = try root.clippingPreviews(width: 120)
    XCTAssertEqual(previews.count, 5, "four built-ins plus the saved selection")
    let savedID = try XCTUnwrap(previews.last?.id)
    let savedSVG = try root.clippingSVG(id: savedID)
    XCTAssertTrue(savedSVG.contains("Reusable lemma"))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(".clippings/notebook.json").path))

    let reopenedRoot = NotesRootAccess(testURL: directory)
    let reopenedSVG = try reopenedRoot.clippingSVG(id: savedID)
    // Each clipboard export deliberately assigns fresh element identities.
    // Compare all content and geometry while excluding only those identities.
    let elementIDPattern = #"id="[sfg]-[^"]+""#
    XCTAssertEqual(
      reopenedSVG.replacingOccurrences(
        of: elementIDPattern, with: #"id="copied-element""#, options: .regularExpression),
      savedSVG.replacingOccurrences(
        of: elementIDPattern, with: #"id="copied-element""#, options: .regularExpression))
    XCTAssertTrue(elementIDs(in: reopenedSVG).isDisjoint(with: elementIDs(in: savedSVG)))

    let (targetReference, target) = try reopenedRoot.createNote(
      title: "Clipping Target",
      parent: FolderReference(path: []),
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let targetCanvas = InkCanvasView(document: target)
    targetCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    targetCanvas.layoutIfNeeded()
    targetCanvas.setViewTransform(.identity)
    try targetCanvas.paste(
      reopenedSVG,
      at: CGPoint(x: 300, y: 300),
      placeAtPointer: true)
    try reopenedRoot.save(target, notebook: targetReference)

    let reopenedTarget = try NotesRootAccess(testURL: directory).load(targetReference)
    let verificationCanvas = InkCanvasView(document: reopenedTarget)
    verificationCanvas.frame = CGRect(x: 0, y: 0, width: 1024, height: 1200)
    verificationCanvas.layoutIfNeeded()
    verificationCanvas.setViewTransform(.identity)
    try verificationCanvas.selectAll(page: 0)
    let pasted = try XCTUnwrap(verificationCanvas.copySelection())
    XCTAssertTrue(pasted.contains("Reusable lemma"))
    XCTAssertTrue(sourceIDs.isDisjoint(with: elementIDs(in: pasted)))
  }

  private func elementIDs(in svg: String) -> Set<String> {
    let pattern = #"\bid="([^"]+)""#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(svg.startIndex..<svg.endIndex, in: svg)
    return Set(expression.matches(in: svg, range: range).compactMap { match in
      guard let idRange = Range(match.range(at: 1), in: svg) else { return nil }
      let id = String(svg[idRange])
      return id.hasPrefix("s-") || id.hasPrefix("f-") || id.hasPrefix("g-") ? id : nil
    })
  }
}
