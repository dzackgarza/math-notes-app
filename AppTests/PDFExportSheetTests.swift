import XCTest
@testable import MathNotes

final class PDFExportSheetTests: XCTestCase {
  func testExportRequestRetainsOriginatingSession() {
    let sessionID = UUID()
    let request = PDFExportRequest(
      sessionID: sessionID,
      destination: .share,
      pageCount: 1,
      currentPage: 0,
      layers: [])

    XCTAssertEqual(request.sessionID, sessionID)
    XCTAssertEqual(request.destination, .share)
  }

  func testDestinationLabelsMatchDocumentMenuActions() {
    XCTAssertEqual(PDFExportDestination.share.menuLabel, "Share")
    XCTAssertEqual(PDFExportDestination.share.title, "Share PDF")
    XCTAssertEqual(PDFExportDestination.share.actionLabel, "Share")
    XCTAssertEqual(PDFExportDestination.export.menuLabel, "Export PDF")
    XCTAssertEqual(PDFExportDestination.export.title, "Export PDF")
    XCTAssertEqual(PDFExportDestination.export.actionLabel, "Export")
  }
}
