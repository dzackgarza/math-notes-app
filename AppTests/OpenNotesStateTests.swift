import CoreGraphics
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

  func testSessionTracksSaveStatusThroughSuccessAndFailure() throws {
    let note = session(["A"], seed: 34)
    XCTAssertEqual(note.saveStatus, .saved)
    XCTAssertEqual(note.saveStatus.label, "Saved")

    note.markUnsaved()
    XCTAssertEqual(note.saveStatus, .pending)
    XCTAssertEqual(note.saveStatus.label, "Unsaved changes")

    try note.performSave {
      XCTAssertEqual(note.saveStatus, .saving)
      XCTAssertEqual(note.saveStatus.label, "Saving…")
    }
    XCTAssertEqual(note.saveStatus, .saved)

    XCTAssertThrowsError(try note.performSave { throw TestFailure.expected })
    XCTAssertEqual(note.saveStatus, .failed)
    XCTAssertEqual(note.saveStatus.label, "Save failed")

    note.markUnsaved()
    XCTAssertEqual(note.saveStatus, .pending)
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

  func testSplitUsesIndependentViewStateForTheSameDocument() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 22)
    note.currentPage = 3
    state.show(note)

    try state.toggleSplit()

    XCTAssertTrue(state.splitOpen)
    XCTAssertTrue(state.secondary === note)
    let secondaryView = try XCTUnwrap(state.secondaryView)
    XCTAssertFalse(secondaryView === note.primaryView)
    XCTAssertEqual(secondaryView.currentPage, 3)

    secondaryView.currentPage = 7
    XCTAssertEqual(note.primaryView.currentPage, 3)
  }

  func testReferenceSelectionKeepsTheLeftTabAndFocusesTheRightPane() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 23)
    let b = session(["B"], seed: 24)
    a.currentPage = 1
    b.currentPage = 5
    state.show(a)
    state.show(b)
    _ = try state.open(
      a.reference,
      save: { _ in },
      load: { _ in XCTFail("Existing tab reloaded"); return a })

    try state.toggleSplit()
    _ = try state.showReference(
      b.reference,
      save: { _ in },
      load: { _ in XCTFail("Existing reference reloaded"); return b })

    XCTAssertTrue(state.selected === a)
    XCTAssertTrue(state.secondary === b)
    XCTAssertTrue(state.focusedSession === b)
    XCTAssertTrue(state.rightFocused)
    XCTAssertEqual(state.secondaryView?.currentPage, 5)
  }

  func testReferenceCanLoadAClosedNoteWithoutChangingTheLeftTab() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 31)
    let b = session(["B"], seed: 32)
    state.show(a)
    try state.toggleSplit()

    var saves: [NotebookReference] = []
    _ = try state.showReference(
      b.reference,
      save: { saves.append($0.reference) },
      load: { reference in
        XCTAssertEqual(reference, b.reference)
        return b
      })

    XCTAssertEqual(saves, [a.reference])
    XCTAssertEqual(state.opened.map(\.reference), [a.reference, b.reference])
    XCTAssertTrue(state.selected === a)
    XCTAssertTrue(state.secondary === b)
  }

  func testClosingTheReferenceNoteClosesTheSplit() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 25)
    let b = session(["B"], seed: 26)
    state.show(a)
    state.show(b)
    _ = try state.open(
      a.reference,
      save: { _ in },
      load: { _ in a })
    try state.toggleSplit()
    _ = try state.showReference(
      b.reference,
      save: { _ in },
      load: { _ in b })

    try state.close(1, save: { _ in })

    XCTAssertFalse(state.splitOpen)
    XCTAssertNil(state.secondary)
    XCTAssertFalse(state.rightFocused)
    XCTAssertTrue(state.active === a)
  }

  func testReferenceCaptureBlocksClosingAndStructuralChanges() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 27)
    state.show(note)
    try state.toggleSplit()
    state.secondaryView?.captureActive = true

    XCTAssertThrowsError(try state.close(0, save: { _ in }))
    XCTAssertThrowsError(try state.showLibrary(save: { _ in }))
    XCTAssertThrowsError(try state.toggleSplit())
    XCTAssertThrowsError(try state.closeSplitIfAllowed())
    XCTAssertTrue(state.splitOpen)
  }

  func testLibraryHidesFocusedSplitStateWithoutClosingTheSplit() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 33)
    state.show(note)
    try state.toggleSplit()
    state.focusRight(true)

    try state.showLibrary(save: { _ in })

    XCTAssertTrue(state.splitOpen)
    XCTAssertNil(state.active)
    XCTAssertNil(state.focusedSession)
    XCTAssertNil(state.focusedView)
  }
  func testReloadingAReferenceReplacesBothControllerIdentities() throws {
    let state = OpenNotesState()
    let first = session(["A"], seed: 28)
    state.show(first)
    try state.toggleSplit()
    state.secondaryView?.currentPage = 4
    let firstSecondaryID = try XCTUnwrap(state.secondaryView?.id)

    let replacement = try XCTUnwrap(
      try state.reloadIfOpen(first.reference) { reference in
        self.session(reference.path, seed: 29)
      })

    XCTAssertNotEqual(first.id, replacement.id)
    let replacementSecondary = try XCTUnwrap(state.secondaryView)
    XCTAssertNotEqual(firstSecondaryID, replacementSecondary.id)
    XCTAssertEqual(replacementSecondary.currentPage, 4)
    XCTAssertTrue(state.secondary === replacement)
  }

  func testLinkedViewsAndSplitAxisRemainWorkspaceState() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 30)
    state.show(note)
    try state.toggleSplit()

    state.toggleLinkedViews()
    XCTAssertTrue(state.linkedViews)
    state.setLinkedViewport(
      EditorLinkedViewport(
        relativeScale: 1.5,
        center: CGPoint(x: 120, y: 240)))
    let linkedViewport = try XCTUnwrap(state.linkedViewport)
    XCTAssertEqual(linkedViewport.relativeScale, CGFloat(1.5))

    state.rotateSplit()
    XCTAssertEqual(state.splitAxis, .vertical)
    state.closeSplit()
    XCTAssertTrue(state.linkedViews)
    XCTAssertNil(state.linkedViewport)
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
