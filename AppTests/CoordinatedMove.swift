import Foundation
import XCTest

@testable import MathNotes

// Moves an item the way Files or a file provider does: a coordinated move by
// another coordinator, which NSFileCoordinator reports to the item's
// presenters (presentedItemDidMove).
func coordinatedMove(_ source: URL, to destination: URL) throws {
  let coordinator = NSFileCoordinator()
  var coordinationError: NSError?
  var moveError: Error?
  coordinator.coordinate(
    writingItemAt: source, options: .forMoving,
    writingItemAt: destination, options: .forReplacing,
    error: &coordinationError
  ) { from, to in
    do {
      try FileManager.default.moveItem(at: from, to: to)
      coordinator.item(at: from, didMoveTo: to)
    } catch {
      moveError = error
    }
  }
  if let coordinationError { throw coordinationError }
  if let moveError { throw moveError }
}

// Waits for the root's presenter to adopt the moved location. Presenter
// callbacks arrive on the presenter's queue and hop to the main thread, so
// an async test must await rather than block the main thread in wait(for:).
@MainActor
func awaitRootURL(_ root: NotesRootAccess, _ url: URL, in test: XCTestCase) async {
  let adopted = XCTNSPredicateExpectation(
    predicate: NSPredicate { _, _ in root.url.standardizedFileURL == url.standardizedFileURL },
    object: nil)
  await test.fulfillment(of: [adopted], timeout: 5)
}
