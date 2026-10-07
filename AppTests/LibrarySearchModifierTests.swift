import XCTest
@testable import MathNotes

final class LibrarySearchModifierTests: XCTestCase {
  func testSearchBindingRetainsWordSeparatorsWhileTyping() {
    var query = ""
    let updates = ["math", "math ", "math n", "math notes"]
    for update in updates {
      query = librarySearchInput(update)
      XCTAssertEqual(query, update)
    }
  }

  func testSearchIsRootOnlyLikeCurrentWebLibrary() {
    XCTAssertTrue(librarySearchEnabled(folderPath: []))
    XCTAssertFalse(librarySearchEnabled(folderPath: ["Course"]))
  }
}
