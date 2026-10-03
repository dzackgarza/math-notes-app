import Foundation
import XCTest
@testable import MathNotes

final class UndoDialTests: XCTestCase {
  func testAccumulatorQuantizesClockwiseAndCounterclockwiseMotion() {
    let step = UndoDialStepAccumulator.stepAngle
    var accumulator = UndoDialStepAccumulator(angle: 0)

    XCTAssertEqual(accumulator.advance(to: 3.4 * step), 3)
    XCTAssertEqual(accumulator.angle, 3 * step, accuracy: 1e-12)
    XCTAssertEqual(accumulator.advance(to: 1.8 * step), -1)
    XCTAssertEqual(accumulator.angle, 2 * step, accuracy: 1e-12)
  }

  func testAccumulatorKeepsSubstepMotionForTheNextUpdate() {
    let step = UndoDialStepAccumulator.stepAngle
    var accumulator = UndoDialStepAccumulator(angle: 0)

    XCTAssertEqual(accumulator.advance(to: 0.6 * step), 0)
    XCTAssertEqual(accumulator.angle, 0, accuracy: 1e-12)
    XCTAssertEqual(accumulator.advance(to: 1.2 * step), 1)
    XCTAssertEqual(accumulator.angle, step, accuracy: 1e-12)
  }

  func testAccumulatorCrossesTheAngleBranchCutInEitherDirection() {
    let step = UndoDialStepAccumulator.stepAngle
    var clockwise = UndoDialStepAccumulator(angle: Double.pi - 0.5 * step)
    var counterclockwise = UndoDialStepAccumulator(angle: -Double.pi + 0.5 * step)

    XCTAssertEqual(clockwise.advance(to: -Double.pi + 1.6 * step), 2)
    XCTAssertEqual(counterclockwise.advance(to: Double.pi - 1.6 * step), -2)
  }

  func testNormalizationKeepsMultipleCounterclockwiseTurnsPositive() {
    let step = UndoDialStepAccumulator.stepAngle

    XCTAssertEqual(
      UndoDialStepAccumulator.normalized(-33 * step),
      31 * step,
      accuracy: 1e-12)
  }
}
