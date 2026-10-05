import Foundation
import XCTest
@testable import MathNotes

final class NotebookLinksTests: XCTestCase {
  private func mark(file: String, id: String = "") -> EngineNavigationMark {
    EngineNavigationMark(
      id: id,
      href: "",
      file: file,
      page: 0,
      x: 12,
      y: 24,
      width: 0,
      height: 0)
  }

  func testSameNotebookLinkUsesTheSourcePageDirectory() throws {
    let note = NotebookReference(path: ["Algebra"])
    let href = try NotebookLink.href(
      source: note,
      sourceFile: "pages/0001.svg",
      target: note,
      mark: mark(file: "pages/0004.svg", id: "b-proof"))

    XCTAssertEqual(href, "0004.svg#b-proof")
    XCTAssertEqual(
      try NotebookLink.resolve(source: note, sourceFile: "pages/0001.svg", href: href),
      .page(reference: note, file: "pages/0004.svg", id: "b-proof"))
  }

  func testFragmentOnlyLinkStaysOnTheCurrentPage() throws {
    let note = NotebookReference(path: ["Algebra"])

    XCTAssertEqual(
      try NotebookLink.resolve(
        source: note,
        sourceFile: "pages/0001.svg",
        href: "#b-proof"),
      .page(reference: note, file: "pages/0001.svg", id: "b-proof"))
  }

  func testCrossNotebookLinkRoundTripsWithoutAnAbsoluteRoot() throws {
    let source = NotebookReference(path: ["Seminar", "Day 1"])
    let target = NotebookReference(path: ["References", "K3 notes"])
    let href = try NotebookLink.href(
      source: source,
      sourceFile: "pages/0007.svg",
      target: target,
      mark: mark(file: "pages/0012.svg", id: "b-period map"))

    XCTAssertEqual(href, "../../../References/K3%20notes/pages/0012.svg#b-period%20map")
    XCTAssertEqual(
      try NotebookLink.resolve(source: source, sourceFile: "pages/0007.svg", href: href),
      .page(reference: target, file: "pages/0012.svg", id: "b-period map"))
  }

  func testExternalLinksAllowOnlyTheWebAndMailSchemes() throws {
    XCTAssertEqual(
      try NotebookLink.resolve(
        source: NotebookReference(path: ["A"]),
        sourceFile: "pages/0001.svg",
        href: "https://example.com/a#b"),
      .external(try XCTUnwrap(URL(string: "https://example.com/a#b"))))

    XCTAssertThrowsError(
      try NotebookLink.resolve(
        source: NotebookReference(path: ["A"]),
        sourceFile: "pages/0001.svg",
        href: "file:///tmp/notes.svg")
    ) { error in
      XCTAssertEqual(error.localizedDescription, "This link protocol is not supported.")
    }
  }

  func testRelativeLinkCannotEscapeTheNotesRoot() {
    XCTAssertThrowsError(
      try NotebookLink.resolve(
        source: NotebookReference(path: ["A"]),
        sourceFile: "pages/0001.svg",
        href: "../../../outside/pages/0001.svg"))
  }
}
