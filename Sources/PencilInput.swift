import CoreGraphics
import InkEngine
import UIKit

struct PencilSampleValues: Equatable {
  var location: CGPoint
  var timeMs: Double
  var pressure: Float
  var altitude: Float
  var azimuth: Float
  var roll: Float
  var has: UInt32
  var phase: UInt8
}

struct PencilSampleFactory {
  static func values(for touch: UITouch, in view: UIView) -> PencilSampleValues {
    let maximumForce = touch.maximumPossibleForce
    let pressure = maximumForce > 0 ? Float(touch.force / maximumForce) : 0
    let phase: UInt8
    switch touch.phase {
    case .began:
      phase = UInt8(INK_PHASE_BEGIN.rawValue)
    case .moved, .stationary:
      phase = UInt8(INK_PHASE_MOVE.rawValue)
    case .ended:
      phase = UInt8(INK_PHASE_END.rawValue)
    case .cancelled:
      phase = UInt8(INK_PHASE_CANCEL.rawValue)
    @unknown default:
      phase = UInt8(INK_PHASE_CANCEL.rawValue)
    }

    return PencilSampleValues(
      location: touch.location(in: view),
      timeMs: touch.timestamp * 1000,
      pressure: pressure,
      altitude: Float(touch.altitudeAngle),
      azimuth: Float(touch.azimuthAngle(in: view)),
      roll: Float(touch.rollAngle),
      has: UInt32(INK_HAS_PRESSURE) | UInt32(INK_HAS_ALTITUDE) | UInt32(INK_HAS_AZIMUTH),
      phase: phase)
  }

  static func make(values: PencilSampleValues, id: UInt32, predicted: Bool) -> InkPenSample {
    var sample = InkPenSample()
    sample.x = values.location.x
    sample.y = values.location.y
    sample.time = values.timeMs
    sample.pressure = values.pressure
    sample.altitude = values.altitude
    sample.azimuth = values.azimuth
    sample.roll = values.roll
    sample.hover_height = 0
    sample.buttons = 0
    sample.has = values.has
    sample.id = id
    sample.tool = UInt8(INK_TOOL_PEN.rawValue)
    sample.phase = values.phase
    sample.predicted = predicted ? 1 : 0
    sample.reserved = 0
    return sample
  }
}

struct PencilSampleIDs {
  private(set) var next: UInt32 = 1
  private var estimates: [Int: UInt32] = [:]

  mutating func issue(estimationIndex: NSNumber?, trackEstimate: Bool) -> UInt32 {
    let id = next
    next &+= 1
    if trackEstimate, let estimationIndex {
      estimates[estimationIndex.intValue] = id
    }
    return id
  }

  func updateID(estimationIndex: NSNumber?) -> UInt32? {
    guard let estimationIndex else { return nil }
    return estimates[estimationIndex.intValue]
  }

  mutating func finish(estimationIndex: NSNumber?) {
    guard let estimationIndex else { return }
    estimates.removeValue(forKey: estimationIndex.intValue)
  }
}
