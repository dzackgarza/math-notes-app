import Foundation
import XCTest
@testable import MathNotes

final class FigurePersistenceTests: XCTestCase {
  @MainActor
  func testFigureIdentityAndDraftSourceSurviveSaveAndReopen() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let noteDirectory = rootDirectory.appendingPathComponent("Figure Note", isDirectory: true)
    let pagesDirectory = noteDirectory.appendingPathComponent("pages", isDirectory: true)
    let assetsDirectory = noteDirectory.appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let figureID = "f-c718xa2kq9mz"
    let notebook = """
      {
        "format": "math-notes",
        "version": 1,
        "title": "Figure Note",
        "pageSize": "A4",
        "template": "blank",
        "layers": [
          { "id": "l-io2oyj", "name": "Ink", "hidden": false, "locked": false }
        ],
        "pages": [
          { "id": "p-ujaqa3", "file": "pages/0001.svg" }
        ]
      }
      """
    let page = """
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:mn="https://github.com/dzackgarza/math-notes-app/ns/1" xmlns:inkml="http://www.w3.org/2003/InkML" id="p-ujaqa3" width="210mm" height="297mm" viewBox="0 0 595.28 841.89">
        <metadata />
        <g id="background" mn:ruling="blank" mn:y-ruling="28.8" mn:y-offset="0" mn:x-ruling="0" mn:margin-left="0">
          <rect width="595.28" height="841.89" fill="#FCFAF5" />
        </g>
        <g id="l-io2oyj">
          <g id="\(figureID)" class="mn-figure" mn:scene="../assets/\(figureID).scene.json" mn:tikz="../assets/\(figureID).tikz">
            <rect id="s-figurebox001" class="mn-shape" fill="none" stroke="#1A1A1A" stroke-width="1" x="30" y="40" width="80" height="50" />
          </g>
        </g>
      </svg>
      """
    let originalSource = "\\begin{tikzpicture}\\draw (0,0) rectangle (1,1);\\end{tikzpicture}\n"
    let draftSource = "\\begin{tikzpicture}\\draw (0,0) -- (2,1);\\end{tikzpicture}\n"

    try Data(notebook.utf8).write(
      to: noteDirectory.appendingPathComponent("notebook.json"), options: .atomic)
    try Data(page.utf8).write(
      to: pagesDirectory.appendingPathComponent("0001.svg"), options: .atomic)
    try Data("{\"version\":1,\"nextId\":1,\"objects\":[],\"selectedId\":null}\n".utf8).write(
      to: assetsDirectory.appendingPathComponent("\(figureID).scene.json"), options: .atomic)
    try Data(originalSource.utf8).write(
      to: assetsDirectory.appendingPathComponent("\(figureID).tikz"), options: .atomic)

    let reference = NotebookReference(path: ["Figure Note"])
    let root = NotesRootAccess(testURL: rootDirectory)
    let document = try await root.load(reference)
    XCTAssertEqual(try document.figureSource(id: figureID), originalSource)

    try document.saveFigureDraft(id: figureID, source: draftSource)
    try root.save(document, notebook: reference)

    let reopened = try await NotesRootAccess(testURL: rootDirectory).load(reference)
    XCTAssertEqual(try reopened.figureSource(id: figureID), draftSource)

    let savedPage = try String(
      contentsOf: pagesDirectory.appendingPathComponent("0001.svg"), encoding: .utf8)
    XCTAssertTrue(savedPage.contains("id=\"\(figureID)\""))
    XCTAssertTrue(savedPage.contains("mn:draft=\"../assets/\(figureID)-"))
  }
}
