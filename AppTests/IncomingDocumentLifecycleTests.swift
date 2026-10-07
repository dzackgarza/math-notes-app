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
}
