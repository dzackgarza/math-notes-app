import Foundation
import XCTest
@testable import MathNotes

@MainActor
final class OpenNotesStateTests: XCTestCase {
  private enum TestFailure: Error {
    case expected
  }

  private func session(
    _ path: [String],
    seed: UInt64
  ) -> OpenNotebookSession {
    OpenNotebookSession(
      reference: NotebookReference(path: path),
      document: EngineDocument(seed: seed))
  }

  func testOpeningAnAlreadyOpenNoteSelectsItWithoutDuplicatingIt() throws {
    let state = OpenNotesState()
    let first = session(["A"], seed: 1)
    state.show(first)

    var saves: [NotebookReference] = []
    let selected = try state.open(
      first.reference,
      save: {
        saves.append($0.reference)
      },
      load: { _ in
        XCTFail("Opening an existing note must not reload it")
        return self.session(["unused"], seed: 2)
      })

    XCTAssertTrue(selected === first)
    XCTAssertEqual(state.opened.count, 1)
    XCTAssertTrue(state.active === first)
    XCTAssertEqual(saves, [first.reference])
  }

  func testSwitchSaveFailureLeavesTheCurrentTabSelected() throws {
    let state = OpenNotesState()
    let first = session(["A"], seed: 3)
    state.show(first)

    XCTAssertThrowsError(
      try state.open(
        NotebookReference(path: ["B"]),
        save: { _ in throw TestFailure.expected },
        load: { _ in self.session(["B"], seed: 4) })
    ) { error in
      guard let stateError = error as? OpenNotesStateError else {
        return XCTFail("Unexpected error: \(error)")
      }
      guard case let .saveFailed(reference, _) = stateError else {
        return XCTFail("Unexpected state error: \(stateError)")
      }
      XCTAssertEqual(reference, first.reference)
    }

    XCTAssertEqual(state.opened.count, 1)
    XCTAssertTrue(state.active === first)
  }

  func testClosingSelectedTabChoosesRightThenPrevious() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 5)
    let b = session(["B"], seed: 6)
    let c = session(["C"], seed: 7)
    state.show(a)
    state.show(b)
    state.show(c)

    _ = try state.open(
      b.reference,
      save: { _ in },
      load: { _ in XCTFail("Existing tab reloaded"); return a })
    XCTAssertTrue(state.active === b)

    try state.close(1, save: { _ in })
    XCTAssertEqual(state.opened.map(\.reference), [a.reference, c.reference])
    XCTAssertTrue(state.active === c)

    try state.close(1, save: { _ in })
    XCTAssertTrue(state.active === a)

    try state.close(0, save: { _ in })
    XCTAssertTrue(state.opened.isEmpty)
    XCTAssertTrue(state.inLibrary)
  }

  func testCloseSaveFailureRetainsTheTargetAndSelection() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 20)
    let b = session(["B"], seed: 21)
    state.show(a)
    state.show(b)

    XCTAssertThrowsError(
      try state.close(1, save: { _ in throw TestFailure.expected }))

    XCTAssertEqual(state.opened.map(\.reference), [a.reference, b.reference])
    XCTAssertTrue(state.active === b)
  }

  func testCaptureBlocksSwitchAndLibraryButOnlyTargetCaptureBlocksClose() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 8)
    let b = session(["B"], seed: 9)
    state.show(a)
    state.show(b)
    a.captureActive = true

    XCTAssertThrowsError(
      try state.open(
        a.reference,
        save: { _ in },
        load: { _ in a }))
    XCTAssertThrowsError(try state.showLibrary(save: { _ in }))

    try state.close(1, save: { _ in })
    XCTAssertTrue(state.active === a)
    XCTAssertThrowsError(try state.close(0, save: { _ in }))
  }

  func testShowLibraryAttemptsToSaveEveryOpenNote() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 10)
    let b = session(["B"], seed: 11)
    let c = session(["C"], seed: 12)
    state.show(a)
    state.show(b)
    state.show(c)

    var saves: [NotebookReference] = []
    XCTAssertThrowsError(
      try state.showLibrary { note in
        saves.append(note.reference)
        if note === b { throw TestFailure.expected }
      })

    XCTAssertEqual(saves, [a.reference, b.reference, c.reference])
    XCTAssertEqual(state.opened.count, 3)
    XCTAssertTrue(state.inLibrary)
    XCTAssertNil(state.active)
  }

  func testCloseUnderIsAtomicWithRespectToTheOpenSessionList() throws {
    let state = OpenNotesState()
    let a = session(["Folder", "A"], seed: 13)
    let b = session(["Folder", "Nested", "B"], seed: 14)
    let c = session(["Other", "C"], seed: 15)
    state.show(a)
    state.show(b)
    state.show(c)

    var saves: [NotebookReference] = []
    XCTAssertThrowsError(
      try state.closeUnder(["Folder"]) { note in
        saves.append(note.reference)
        if note === b { throw TestFailure.expected }
      })
    XCTAssertEqual(saves, [a.reference, b.reference])
    XCTAssertEqual(state.opened.count, 3)

    try state.closeUnder(["Folder"], save: { _ in })
    XCTAssertEqual(state.opened.map(\.reference), [c.reference])
    XCTAssertTrue(state.active === c)
  }

  func testPerNoteViewStateSurvivesTabSwitches() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 16)
    let b = session(["B"], seed: 17)
    a.currentPage = 4
    a.documentRevision = 8
    a.bookmarkMode = true
    b.currentPage = 2
    state.show(a)
    state.show(b)

    _ = try state.open(
      a.reference,
      save: { _ in },
      load: { _ in XCTFail("Existing tab reloaded"); return b })

    XCTAssertEqual(a.currentPage, 4)
    XCTAssertEqual(a.documentRevision, 8)
    XCTAssertTrue(a.bookmarkMode)
    XCTAssertEqual(b.currentPage, 2)
  }

  func testReloadReplacesTheControllerIdentityAtTheSameTab() throws {
    let state = OpenNotesState()
    let first = session(["A"], seed: 18)
    state.show(first)

    let replacement = try XCTUnwrap(
      try state.reloadIfOpen(first.reference) { reference in
        self.session(reference.path, seed: 19)
      })

    XCTAssertNotEqual(first.id, replacement.id)
    XCTAssertTrue(state.active === replacement)
    XCTAssertEqual(state.opened.count, 1)
  }
}
