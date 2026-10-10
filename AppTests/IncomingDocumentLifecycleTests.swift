import Foundation
import XCTest
@testable import MathNotes

final class IncomingDocumentLifecycleTests: XCTestCase {
  @MainActor
  func testSceneDelegateQueuesIncomingDocumentUntilMatchingConsumerClearsIt() {
    let delegate = MathNotesSceneDelegate()
    let first = URL(fileURLWithPath: "/tmp/first.pdf")
    let second = URL(fileURLWithPath: "/tmp/second.pdf")

    delegate.receiveIncomingDocumentURL(first)
    let firstIncoming = delegate.incomingDocument
    XCTAssertEqual(firstIncoming?.url, first)

    delegate.clearIncomingDocument(UUID())
    XCTAssertEqual(delegate.incomingDocument?.id, firstIncoming?.id)

    delegate.receiveIncomingDocumentURL(second)
    let secondIncoming = delegate.incomingDocument
    XCTAssertEqual(secondIncoming?.url, second)
    XCTAssertNotEqual(secondIncoming?.id, firstIncoming?.id)

    if let id = secondIncoming?.id {
      delegate.clearIncomingDocument(id)
    }
    XCTAssertNil(delegate.incomingDocument)
  }

  // SideStore's Open button launches the app with its own scheme (device
  // capture 2026-10-09 23:27:21: "url: sidestore-dev.zack.mathnotes.73DJ2N3GT2://").
  // That launch carries no document, so nothing is imported and no
  // "Math Notes can import PDF files." alert appears.
  @MainActor
  func testSideStoreLaunchURLIsNoIncomingDocument() throws {
    let delegate = MathNotesSceneDelegate()
    let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
    delegate.receiveIncomingDocumentURL(try XCTUnwrap(URL(string: "sidestore-\(bundle)://")))
    XCTAssertNil(delegate.incomingDocument)
  }
}
