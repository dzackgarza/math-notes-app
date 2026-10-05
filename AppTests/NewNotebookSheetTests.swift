import XCTest
@testable import MathNotes

final class NewNotebookSheetTests: XCTestCase {
  func testFormStartsFromNotebookDefaultsWithoutInheritingText() {
    let root = FolderReference(path: [])
    let course = FolderReference(path: ["Course"])
    let state = NewNotebookFormState(
      folders: [root, course],
      initialParent: course,
      defaults: LibraryFolderDetails(
        description: "Parent description",
        paper: "grid-medium",
        coverColor: "#5B2328",
        coverStyle: "spine",
        tags: ["Algebra"]))

    XCTAssertEqual(state.title, "")
    XCTAssertEqual(state.description, "")
    XCTAssertEqual(state.parent, course)
    XCTAssertEqual(state.paper, "grid-medium")
    XCTAssertEqual(state.coverColor, "#5B2328")
    XCTAssertEqual(state.coverStyle, "spine")
    XCTAssertEqual(state.tags, ["Algebra"])
  }

  func testRequestCarriesNotebookMetadataAndLocation() {
    let root = FolderReference(path: [])
    let course = FolderReference(path: ["Course"])
    var state = NewNotebookFormState(
      folders: [root, course],
      initialParent: root,
      defaults: LibraryFolderDetails(
        description: "",
        paper: "dotted",
        coverColor: "#24324A",
        coverStyle: "classic",
        tags: []))
    state.title = "  Topology  "
    state.description = "Seminar notes"
    state.parent = course
    state.paper = "lined-medium"
    state.coverColor = "#2F4A3A"
    state.coverStyle = "spine"
    state.tags = ["Seminar"]

    let request = state.request
    XCTAssertEqual(request.title, "Topology")
    XCTAssertEqual(request.parent, course)
    XCTAssertEqual(
      request.details,
      LibraryFolderDetails(
        description: "Seminar notes",
        paper: "lined-medium",
        coverColor: "#2F4A3A",
        coverStyle: "spine",
        tags: ["Seminar"]))
  }
}
