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

  func testAutosaveCheckpointMakesPendingEditsRecoverable() throws {
    let note = session(["A"], seed: 35)
    var checkpoints = 0

    note.scheduleAutosave(
      after: .seconds(60),
      checkpoint: { checkpoints += 1 }
    ) {}

    XCTAssertEqual(checkpoints, 1)
    XCTAssertEqual(note.saveStatus, .recoverable)
    XCTAssertEqual(note.saveStatus.label, "Pending file save")
    try note.performSave {}
    XCTAssertEqual(note.saveStatus, .saved)
  }

  func testAutosaveDebouncesAndExplicitSaveCancelsPendingWork() async throws {
    let note = session(["A"], seed: 35)
    var saves = 0
    let fired = expectation(description: "debounced autosave fires")

    note.scheduleAutosave(after: .zero) {
      saves += 1
      try? note.performSave {}
    }
    note.scheduleAutosave(after: .zero) {
      saves += 1
      try? note.performSave {}
      fired.fulfill()
    }
    XCTAssertEqual(note.saveStatus, .pending)

    await fulfillment(of: [fired], timeout: 1)
    XCTAssertEqual(saves, 1)
    XCTAssertEqual(note.saveStatus, .saved)

    let canceled = expectation(description: "explicit save cancels pending autosave")
    canceled.isInverted = true
    note.scheduleAutosave(after: .seconds(60)) {
      saves += 1
      canceled.fulfill()
    }
    try note.performSave {}
    await fulfillment(of: [canceled], timeout: 0.05)
    XCTAssertEqual(saves, 1)
    XCTAssertEqual(note.saveStatus, .saved)
  }

  func testExternalImportSavesTheActiveSessionBeforeSwitching() throws {
    let state = OpenNotesState()
    let inactive = session(["Inactive"], seed: 41)
    let active = session(["Active"], seed: 42)
    state.show(inactive)
    state.show(active)
    inactive.markUnsaved()
    active.markUnsaved()

    var saved: [NotebookReference] = []
    try state.prepareForExternalImport { session in
      saved.append(session.reference)
      try session.performSave {}
    }

    XCTAssertEqual(saved, [active.reference])
    XCTAssertEqual(inactive.saveStatus, .pending)
    XCTAssertEqual(active.saveStatus, .saved)
  }

  func testExternalImportDoesNotBypassAFailedActiveSession() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 43)
    state.show(note)
    XCTAssertThrowsError(try note.performSave { throw TestFailure.expected })
    XCTAssertEqual(note.saveStatus, .failed)

    XCTAssertThrowsError(
      try state.prepareForExternalImport { session in
        try session.performSave { throw TestFailure.expected }
      }) { error in
        guard case let OpenNotesStateError.saveFailed(reference, _) = error else {
          return XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(reference, note.reference)
      }
    XCTAssertEqual(note.saveStatus, .failed)
  }

  func testExternalImportIsBlockedByCaptureBeforeSaving() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 42)
    state.show(note)
    note.captureActive = true
    note.markUnsaved()

    var saves = 0
    XCTAssertThrowsError(
      try state.prepareForExternalImport { _ in saves += 1 }) { error in
        guard case OpenNotesStateError.captureInProgress = error else {
          return XCTFail("Unexpected error: \(error)")
        }
      }
    XCTAssertEqual(saves, 0)
    XCTAssertEqual(note.saveStatus, .pending)
  }

  func testSavePendingOnlyFlushesPendingSessions() throws {
    let state = OpenNotesState()
    let saved = session(["Saved"], seed: 36)
    let pending = session(["Pending"], seed: 37)
    let failed = session(["Failed"], seed: 38)
    state.show(saved)
    state.show(pending)
    state.show(failed)
    pending.scheduleAutosave(
      after: .seconds(60),
      checkpoint: {}
    ) {}
    XCTAssertEqual(pending.saveStatus, .recoverable)
    XCTAssertThrowsError(try failed.performSave { throw TestFailure.expected })

    var savedPaths: [[String]] = []
    try state.savePending { note in
      savedPaths.append(note.reference.path)
      try note.performSave {}
    }

    XCTAssertEqual(savedPaths, [["Pending"]])
    XCTAssertEqual(saved.saveStatus, .saved)
    XCTAssertEqual(pending.saveStatus, .saved)
    XCTAssertEqual(failed.saveStatus, .failed)
  }

  func testSavePendingAttemptsEveryPendingSessionAfterAFailure() throws {
    let state = OpenNotesState()
    let first = session(["First"], seed: 39)
    let second = session(["Second"], seed: 40)
    state.show(first)
    state.show(second)
    first.markUnsaved()
    second.markUnsaved()

    var attempted: [[String]] = []
    XCTAssertThrowsError(
      try state.savePending { note in
        attempted.append(note.reference.path)
        if note.id == first.id { throw TestFailure.expected }
        try note.performSave {}
      })

    XCTAssertEqual(attempted, [["First"], ["Second"]])
    XCTAssertEqual(first.saveStatus, .pending)
    XCTAssertEqual(second.saveStatus, .saved)
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

  func testFigureEditorCaptureTracksTheOriginatingPane() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 43)
    state.show(note)

    XCTAssertTrue(state.setCapture(viewID: note.primaryView.id, active: true))
    XCTAssertThrowsError(try state.requireNoCapture("switching notes"))
    XCTAssertTrue(state.setCapture(viewID: note.primaryView.id, active: false))
    XCTAssertNoThrow(try state.requireNoCapture("switching notes"))

    try state.toggleSplit()
    // The split opens unfocused on the right; address its view directly.
    let secondary = try XCTUnwrap(state.secondaryView)
    XCTAssertTrue(state.setCapture(viewID: secondary.id, active: true))
    XCTAssertThrowsError(try state.requireNoCapture("switching notes"))
    XCTAssertTrue(state.setCapture(viewID: secondary.id, active: false))
    XCTAssertNoThrow(try state.requireNoCapture("switching notes"))
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

  func testCloseAllAllowsCaptureWhenChangingNotesFolders() throws {
    let state = OpenNotesState()
    let a = session(["A"], seed: 34)
    let b = session(["B"], seed: 35)
    state.show(a)
    state.show(b)
    a.captureActive = true

    var saves: [NotebookReference] = []
    try state.closeAll { note in
      saves.append(note.reference)
    }

    XCTAssertEqual(saves, [a.reference, b.reference])
    XCTAssertTrue(state.opened.isEmpty)
    XCTAssertTrue(state.inLibrary)
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

  func testCloseUnderClampsTheTabIndexLikeWebRelease() throws {
    let state = OpenNotesState()
    let removed = session(["Folder", "A"], seed: 40)
    let middle = session(["Other", "B"], seed: 41)
    let selected = session(["Other", "C"], seed: 42)
    let right = session(["Other", "D"], seed: 43)
    state.show(removed)
    state.show(middle)
    state.show(selected)
    state.show(right)
    _ = try state.open(
      selected.reference,
      save: { _ in },
      load: { _ in selected })

    try state.closeUnder(["Folder"], save: { _ in })

    XCTAssertEqual(state.opened.map(\.reference), [middle.reference, selected.reference, right.reference])
    XCTAssertTrue(state.active === right)
  }

  func testCloseUnderStopsAtTheFirstSaveFailure() throws {
    let state = OpenNotesState()
    let a = session(["Folder", "A"], seed: 38)
    let b = session(["Folder", "B"], seed: 39)
    state.show(a)
    state.show(b)

    var saves: [NotebookReference] = []
    XCTAssertThrowsError(
      try state.closeUnder(["Folder"]) { note in
        saves.append(note.reference)
        if note === a { throw TestFailure.expected }
      })

    XCTAssertEqual(saves, [a.reference])
    XCTAssertEqual(state.opened.map(\.reference), [a.reference, b.reference])
  }

  func testCloseUnderAllowsCaptureWhenRelocatingEntries() throws {
    let state = OpenNotesState()
    let a = session(["Folder", "A"], seed: 36)
    let b = session(["Other", "B"], seed: 37)
    state.show(a)
    state.show(b)
    a.captureActive = true

    var saves: [NotebookReference] = []
    try state.closeUnder(["Folder"]) { note in
      saves.append(note.reference)
    }

    XCTAssertEqual(saves, [a.reference])
    XCTAssertEqual(state.opened.map(\.reference), [b.reference])
    XCTAssertTrue(state.active === b)
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

  func testReferenceCaptureBlocksDocumentChangesButNotPaneClose() throws {
    let state = OpenNotesState()
    let note = session(["A"], seed: 27)
    state.show(note)
    try state.toggleSplit()
    state.secondaryView?.captureActive = true

    XCTAssertThrowsError(try state.close(0, save: { _ in }))
    XCTAssertThrowsError(try state.showLibrary(save: { _ in }))
    XCTAssertThrowsError(try state.toggleSplit())
    XCTAssertTrue(state.splitOpen)

    state.closeSplit()
    XCTAssertFalse(state.splitOpen)
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
  func testReloadingAReferenceClosesTheSplitAndSelectsTheReplacement() throws {
    let state = OpenNotesState()
    let left = session(["Left"], seed: 28)
    let reference = session(["Reference"], seed: 29)
    state.show(left)
    try state.toggleSplit()
    _ = try state.showReference(
      reference.reference,
      save: { _ in },
      load: { _ in reference })

    let replacement = try XCTUnwrap(
      try state.reloadIfOpen(
        reference.reference,
        save: { _ in },
        load: { ref in self.session(ref.path, seed: 30) }))

    XCTAssertFalse(state.splitOpen)
    XCTAssertTrue(state.active === replacement)
    XCTAssertEqual(state.opened.map(\.reference), [left.reference, reference.reference])
    XCTAssertNotEqual(reference.id, replacement.id)
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

  func testReloadSavesTheTabExposedByReleasingTheResolvedNote() throws {
    let state = OpenNotesState()
    let first = session(["A"], seed: 34)
    let resolved = session(["B"], seed: 35)
    state.show(first)
    state.show(resolved)
    var events: [String] = []

    let replacement = try XCTUnwrap(
      try state.reloadIfOpen(
        resolved.reference,
        save: { events.append("save \($0.reference.name)") },
        load: { reference in
          events.append("load \(reference.name)")
          return self.session(reference.path, seed: 36)
        }))

    XCTAssertEqual(events, ["save A", "load B"])
    XCTAssertTrue(state.active === replacement)
    XCTAssertEqual(state.opened.map(\.reference), [first.reference, resolved.reference])
  }

  func testReloadMovesTheResolvedNoteToTheSelectedLastTab() throws {
    let state = OpenNotesState()
    let first = session(["A"], seed: 18)
    let second = session(["B"], seed: 19)
    state.show(first)
    state.show(second)
    _ = try state.open(
      first.reference,
      save: { _ in },
      load: { _ in first })

    let replacement = try XCTUnwrap(
      try state.reloadIfOpen(
        first.reference,
        save: { _ in },
        load: { reference in self.session(reference.path, seed: 20) }))

    XCTAssertNotEqual(first.id, replacement.id)
    XCTAssertTrue(state.active === replacement)
    XCTAssertEqual(state.opened.map(\.reference), [second.reference, first.reference])
  }
}
