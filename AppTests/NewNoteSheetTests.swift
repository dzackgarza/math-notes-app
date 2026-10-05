import XCTest
@testable import MathNotes

final class NewNoteSheetTests: XCTestCase {
  func testPaperChoicesAndLabelsMatchWebCreationSheet() {
    XCTAssertEqual(
      NewNotePaperStyle.choices,
      ["dotted", "grid-medium", "lined-medium", "blank", "grid-fine"])
    XCTAssertEqual(NewNotePaperStyle.shortLabel("dotted"), "Dot")
    XCTAssertEqual(NewNotePaperStyle.shortLabel("grid-medium"), "Grid")
    XCTAssertEqual(NewNotePaperStyle.shortLabel("lined-medium"), "Lined")
    XCTAssertEqual(NewNotePaperStyle.shortLabel("blank"), "Plain")
    XCTAssertEqual(NewNotePaperStyle.shortLabel("grid-fine"), "Graph")
    XCTAssertEqual(NewNotePaperStyle.summaryLabel("grid-medium"), "Grid paper")
    XCTAssertEqual(NewNotePaperStyle.summaryLabel("lined-wide"), "Lined paper, wide")
    XCTAssertEqual(NewNotePaperStyle.summaryLabel("grid-coarse"), "Grid paper, coarse")
    XCTAssertEqual(NewNotePaperStyle.summaryLabel("custom-template"), "custom-template")
  }

  func testPagePaperLabelsAndOrderMatchWebSheet() {
    XCTAssertEqual(PagePaperSheet.displayLabel("dotted"), "Dot paper")
    XCTAssertEqual(PagePaperSheet.displayLabel("custom-template"), "custom-template")
    XCTAssertEqual(
      PagePaperSheet.sortedTemplates([
        "blank", "lined-wide", "dotted", "grid-fine", "grid-medium", "grid-coarse"
      ]),
      ["dotted", "grid-fine", "grid-medium", "grid-coarse", "lined-wide", "blank"])
  }

  func testUnlistedFolderPaperDefaultIsPreservedUntilChanged() {
    let root = FolderReference(path: [])
    let state = NewNoteFormState(
      folders: [root],
      templates: ["blank", "lined-wide"],
      initialParent: root,
      folderDefaults: LibraryFolderDetails(
        description: "",
        paper: "lined-wide",
        coverColor: "#24324A",
        coverStyle: "classic",
        tags: []),
      draft: nil)

    XCTAssertEqual(state.template, "lined-wide")
    XCTAssertFalse(NewNotePaperStyle.choices.contains(state.template))
  }

  func testDefaultsComeFromCurrentFolderWithoutDraft() {
    let root = FolderReference(path: [])
    let analysis = FolderReference(path: ["Analysis"])
    let state = NewNoteFormState(
      folders: [root, analysis],
      templates: ["blank", "grid-medium"],
      initialParent: analysis,
      folderDefaults: LibraryFolderDetails(
        description: "",
        paper: "grid-medium",
        coverColor: "#24324A",
        coverStyle: "classic",
        tags: ["Research"]),
      draft: nil)

    XCTAssertEqual(state.title, "")
    XCTAssertEqual(state.parent, analysis)
    XCTAssertEqual(state.template, "grid-medium")
    XCTAssertEqual(state.tags, ["Research"])
    XCTAssertEqual(state.pageSize, .a4)
    XCTAssertEqual(state.orientation, .portrait)
  }

  func testDraftOverridesFolderDefaultsAndDefaultsMissingGeometry() {
    let state = NewNoteFormState(
      folders: [FolderReference(path: []), FolderReference(path: ["Analysis"])],
      templates: ["blank", "lined-medium"],
      initialParent: FolderReference(path: ["Analysis"]),
      folderDefaults: LibraryFolderDetails(
        description: "",
        paper: "grid-medium",
        coverColor: "#24324A",
        coverStyle: "classic",
        tags: ["Folder tag"]),
      draft: NewNoteDraft(
        folder: ["Drafts"],
        title: "Derived categories",
        template: "lined-medium",
        tags: ["Seminar"],
        pageSize: nil,
        orientation: nil))

    XCTAssertEqual(state.title, "Derived categories")
    XCTAssertEqual(state.parent, FolderReference(path: ["Drafts"]))
    XCTAssertEqual(state.template, "lined-medium")
    XCTAssertEqual(state.tags, ["Seminar"])
    XCTAssertEqual(state.pageSize, .a4)
    XCTAssertEqual(state.orientation, .portrait)
  }

  func testRequestTrimsTitleLikeWebCreationSheet() {
    var state = NewNoteFormState(
      folders: [FolderReference(path: [])],
      templates: ["blank"],
      initialParent: FolderReference(path: []),
      folderDefaults: LibraryFolderDetails(
        description: "",
        paper: "blank",
        coverColor: "#24324A",
        coverStyle: "classic",
        tags: []),
      draft: nil)
    state.title = "  Derived categories  "

    XCTAssertEqual(state.request.title, "Derived categories")
  }

  func testStartingTemplateReplacesSettingsButKeepsTitle() {
    var state = NewNoteFormState(
      folders: [FolderReference(path: [])],
      templates: ["blank", "dotted"],
      initialParent: FolderReference(path: []),
      folderDefaults: LibraryFolderDetails(
        description: "",
        paper: "blank",
        coverColor: "#24324A",
        coverStyle: "classic",
        tags: []),
      draft: nil)
    state.title = "Keep this title"

    state.apply(
      NewNoteStartingTemplate(
        name: "Seminar",
        folder: ["Courses"],
        paper: "dotted",
        pageSize: "letter",
        orientation: "landscape",
        tags: ["Topology", "Seminar"]))

    XCTAssertEqual(state.title, "Keep this title")
    XCTAssertEqual(state.parent, FolderReference(path: ["Courses"]))
    XCTAssertEqual(state.template, "dotted")
    XCTAssertEqual(state.tags, ["Topology", "Seminar"])
    XCTAssertEqual(state.pageSize, .letter)
    XCTAssertEqual(state.orientation, .landscape)
  }
}
