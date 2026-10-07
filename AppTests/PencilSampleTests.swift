import CoreGraphics
import InkEngine
import XCTest
@testable import MathNotes

final class PencilSampleTests: XCTestCase {
  func testSampleFactoryMapsValuesIntoTheEngineABI() {
    let has = PencilSampleFactory.pencilCapabilities(maximumPossibleForce: 4)
    XCTAssertNotEqual(has & UInt32(INK_HAS_ROLL), 0)
    let values = PencilSampleValues(
      location: CGPoint(x: 42.5, y: 87.25),
      timeMs: 1234,
      pressure: 0.625,
      altitude: 1.1,
      azimuth: 2.2,
      roll: 0.3,
      hoverHeight: 0.75,
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
    XCTAssertEqual(sample.hover_height, 0.75)
    XCTAssertEqual(sample.has, has)
    XCTAssertEqual(sample.id, 17)
    XCTAssertEqual(sample.tool, UInt8(INK_TOOL_PEN.rawValue))
    XCTAssertEqual(sample.phase, UInt8(INK_PHASE_MOVE.rawValue))
    XCTAssertEqual(sample.predicted, 1)
  }

  func testHoverSampleAdvertisesMeasuredHoverHeight() {
    let values = PencilSampleFactory.hoverValues(
      location: CGPoint(x: 12, y: 34),
      timeMs: 99,
      altitude: 0.8,
      azimuth: 1.2,
      roll: 0.4,
      hoverHeight: 1.25)
    let sample = PencilSampleFactory.make(values: values, id: 5, predicted: false)

    XCTAssertEqual(sample.phase, UInt8(INK_PHASE_HOVER.rawValue))
    XCTAssertEqual(sample.pressure, 0)
    XCTAssertEqual(sample.hover_height, 1)
    XCTAssertNotEqual(sample.has & UInt32(INK_HAS_HOVER_HEIGHT), 0)
  }

  func testEstimatedPropertyUpdateUsesOriginalSampleIDAndUpdatedValues() {
    var ids = PencilSampleIDs()
    let index = NSNumber(value: 41)
    let original = ids.issue(estimationIndex: index, trackEstimate: true)
    _ = ids.issue(estimationIndex: nil, trackEstimate: false)

    let updatedValues = PencilSampleValues(
      location: CGPoint(x: 14, y: 27),
      timeMs: 2500,
      pressure: 0.875,
      altitude: 0.9,
      azimuth: 1.4,
      roll: 0.2,
      hoverHeight: 0,
      has: PencilSampleFactory.pencilCapabilities(maximumPossibleForce: 4),
      phase: UInt8(INK_PHASE_MOVE.rawValue))
    let update = ids.estimatedUpdate(
      values: updatedValues,
      estimationIndex: index,
      finished: true)

    XCTAssertEqual(update?.id, original)
    XCTAssertEqual(update?.x, 14)
    XCTAssertEqual(update?.y, 27)
    XCTAssertEqual(update?.time, 2500)
    XCTAssertEqual(update?.pressure, 0.875)
    XCTAssertEqual(update?.altitude, 0.9)
    XCTAssertEqual(update?.azimuth, 1.4)
    XCTAssertEqual(update?.roll, 0.2)
    XCTAssertEqual(update?.predicted, 0)
    XCTAssertNil(ids.updateID(estimationIndex: index))
  }
  func testCancelPendingEstimatesDiscardsCancelledStrokeUpdates() {
    var ids = PencilSampleIDs()
    let index = NSNumber(value: 17)
    _ = ids.issue(estimationIndex: index, trackEstimate: true)
    XCTAssertNotNil(ids.updateID(estimationIndex: index))

    ids.cancelPendingEstimates()
    XCTAssertNil(ids.updateID(estimationIndex: index))
  }

  func testPressureCapabilityRequiresAUsableForceRange() {
    let withoutPressure = PencilSampleFactory.pencilCapabilities(maximumPossibleForce: 0)
    let withPressure = PencilSampleFactory.pencilCapabilities(maximumPossibleForce: 4)

    XCTAssertEqual(withoutPressure & UInt32(INK_HAS_PRESSURE), 0)
    XCTAssertNotEqual(withPressure & UInt32(INK_HAS_PRESSURE), 0)
    XCTAssertEqual(
      withoutPressure & (UInt32(INK_HAS_ALTITUDE) | UInt32(INK_HAS_AZIMUTH) | UInt32(INK_HAS_ROLL)),
      UInt32(INK_HAS_ALTITUDE) | UInt32(INK_HAS_AZIMUTH) | UInt32(INK_HAS_ROLL))
  }

  func testUTCOffsetMapsSystemUptimeSamplesOntoUnixTime() {
    let offset = pencilUTCOffsetMilliseconds(
      utcNow: 1_760_000_123.456,
      systemUptime: 123_456.789)

    XCTAssertEqual(
      123_456_789 + offset,
      1_760_000_123_456,
      accuracy: 0.001)
  }

  func testCoalescedBatchPhasesMarkOnlyBatchBoundaries() {
    XCTAssertEqual(
      (0..<3).map { PencilSampleFactory.batchPhase(eventPhase: .began, index: $0, count: 3) },
      [
        UInt8(INK_PHASE_BEGIN.rawValue),
        UInt8(INK_PHASE_MOVE.rawValue),
        UInt8(INK_PHASE_MOVE.rawValue),
      ])
    XCTAssertEqual(
      (0..<3).map { PencilSampleFactory.batchPhase(eventPhase: .ended, index: $0, count: 3) },
      [
        UInt8(INK_PHASE_MOVE.rawValue),
        UInt8(INK_PHASE_MOVE.rawValue),
        UInt8(INK_PHASE_END.rawValue),
      ])
    XCTAssertEqual(
      (0..<2).map { PencilSampleFactory.batchPhase(eventPhase: .cancelled, index: $0, count: 2) },
      [UInt8(INK_PHASE_MOVE.rawValue), UInt8(INK_PHASE_CANCEL.rawValue)])
  }

}
