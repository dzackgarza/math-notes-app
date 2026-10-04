import XCTest
@testable import MathNotes

final class LibrarySearchModifierTests: XCTestCase {
  func testSearchIsRootOnlyLikeCurrentWebLibrary() {
    XCTAssertTrue(librarySearchEnabled(folderPath: []))
    XCTAssertFalse(librarySearchEnabled(folderPath: ["Course"]))
  }
}
