import XCTest
@testable import MathNotes

final class PageMenuAvailabilityTests: XCTestCase {
  func testDrawingModeMatchesWebPageMenuGuards() {
    let available = PageMenuAvailability(drawing: true, pageCount: 3)

    XCTAssertFalse(available.pageOverview)
    XCTAssertFalse(available.goToPage)
    XCTAssertFalse(available.pageMutation)
    XCTAssertTrue(available.selectPage)
    XCTAssertFalse(available.clearPage)
    XCTAssertFalse(available.paper)
    XCTAssertTrue(available.bookmarks)
    XCTAssertFalse(available.addBookmark)
    XCTAssertFalse(available.layers)
    XCTAssertFalse(available.deletePage)
  }

  func testNormalModeKeepsCountDependentActions() {
    let empty = PageMenuAvailability(drawing: false, pageCount: 0)
    XCTAssertFalse(empty.goToPage)
    XCTAssertFalse(empty.deletePage)
    XCTAssertTrue(empty.pageOverview)
    XCTAssertTrue(empty.pageMutation)

    let multiple = PageMenuAvailability(drawing: false, pageCount: 2)
    XCTAssertTrue(multiple.goToPage)
    XCTAssertTrue(multiple.deletePage)
  }
}
