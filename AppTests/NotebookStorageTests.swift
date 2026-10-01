import Foundation
import XCTest
@testable import MathNotes

final class NotebookStorageTests: XCTestCase {
  func testWritesAssetsThenPagesThenNotebookMetadataThenDeletes() {
    let changes = [
      EngineFileChange(path: "pages/0002.svg", kind: .delete),
      EngineFileChange(path: "notebook.json", kind: .write(Data("index".utf8))),
      EngineFileChange(path: "pages/0001.svg", kind: .write(Data("page".utf8))),
      EngineFileChange(path: "assets/diagram.png", kind: .write(Data([1, 2, 3]))),
      EngineFileChange(path: "assets/old.png", kind: .delete),
    ]

    XCTAssertEqual(
      orderedNotebookChanges(changes).map(\.path),
      [
        "assets/diagram.png",
        "pages/0001.svg",
        "notebook.json",
        "assets/old.png",
        "pages/0002.svg",
      ])
  }
}
