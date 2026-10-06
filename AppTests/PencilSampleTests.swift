import CoreGraphics
import InkEngine
import XCTest
@testable import MathNotes

final class PencilSampleTests: XCTestCase {
  func testSampleFactoryMapsValuesIntoTheEngineABI() {
    let has = PencilSampleFactory.pencilCapabilities
    XCTAssertNotEqual(has & UInt32(INK_HAS_ROLL), 0)
    let values = PencilSampleValues(
      location: CGPoint(x: 42.5, y: 87.25),
      timeMs: 1234,
      pressure: 0.625,
      altitude: 1.1,
      azimuth: 2.2,
      roll: 0.3,
      has: has,
      phase: UInt8(INK_PHASE_MOVE.rawValue))

    let sample = PencilSampleFactory.make(values: values, id: 17, predicted: true)

    XCTAssertEqual(sample.x, 42.5)
    XCTAssertEqual(sample.y, 87.25)
    XCTAssertEqual(sample.time, 1234)
    XCTAssertEqual(sample.pressure, 0.625)
    XCTAssertEqual(sample.altitude, 1.1)
    XCTAssertEqual(sample.azimuth, 2.2)
    XCTAssertEqual(sample.roll, 0.3)
    XCTAssertEqual(sample.has, has)
    XCTAssertEqual(sample.id, 17)
    XCTAssertEqual(sample.tool, UInt8(INK_TOOL_PEN.rawValue))
    XCTAssertEqual(sample.phase, UInt8(INK_PHASE_MOVE.rawValue))
    XCTAssertEqual(sample.predicted, 1)
  }

  func testEstimatedPropertyUpdateUsesTheOriginalSampleID() {
    var ids = PencilSampleIDs()
    let index = NSNumber(value: 41)

    let original = ids.issue(estimationIndex: index, trackEstimate: true)
    _ = ids.issue(estimationIndex: nil, trackEstimate: false)

    XCTAssertEqual(ids.updateID(estimationIndex: index), original)

    ids.finish(estimationIndex: index)
    XCTAssertNil(ids.updateID(estimationIndex: index))
  }
}
