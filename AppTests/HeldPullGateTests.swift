import XCTest
@testable import MathNotes

final class HeldPullGateTests: XCTestCase {
  func testReleaseBeforeHoldDoesNotAddPage() {
    var gate = HeldPullGate()
    gate.becameReady(at: 10)

    XCTAssertFalse(gate.release(at: 10.349))
  }

  func testReleaseAfterHoldAddsOnePageAndConsumesReadiness() {
    var gate = HeldPullGate()
    gate.becameReady(at: 10)

    XCTAssertTrue(gate.release(at: 10.35))
    XCTAssertFalse(gate.release(at: 11))
  }

  func testLeavingReadyCancelsTheHold() {
    var gate = HeldPullGate()
    gate.becameReady(at: 10)
    gate.leftReady()

    XCTAssertFalse(gate.release(at: 11))
  }
}
