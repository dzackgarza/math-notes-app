import CoreGraphics
import Foundation
import InkEngine
import UIKit

func pencilUTCOffsetMilliseconds(
  utcNow: TimeInterval = Date().timeIntervalSince1970,
  systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
) -> Double {
  (utcNow - systemUptime) * 1000
}

struct PencilSampleValues: Equatable {
  var location: CGPoint
  var timeMs: Double
  var pressure: Float
  var altitude: Float
  var azimuth: Float
  var roll: Float
  var hoverHeight: Float
  var has: UInt32
  var phase: UInt8
}

struct PencilSampleFactory {
  private static let pencilPoseCapabilities =
    UInt32(INK_HAS_ALTITUDE) |
    UInt32(INK_HAS_AZIMUTH) |
    UInt32(INK_HAS_ROLL)

  static func pencilCapabilities(maximumPossibleForce: CGFloat) -> UInt32 {
    pencilPoseCapabilities | (maximumPossibleForce > 0 ? UInt32(INK_HAS_PRESSURE) : 0)
  }

  static func values(for touch: UITouch, in view: UIView) -> PencilSampleValues {
    let maximumForce = touch.maximumPossibleForce
    let pressure = maximumForce > 0 ? Float(touch.force / maximumForce) : 0
    return PencilSampleValues(
      location: touch.location(in: view),
      timeMs: touch.timestamp * 1000,
      pressure: pressure,
      altitude: Float(touch.altitudeAngle),
      azimuth: Float(touch.azimuthAngle(in: view)),
      roll: Float(touch.rollAngle),
      hoverHeight: 0,
      has: pencilCapabilities(maximumPossibleForce: maximumForce),
      phase: phase(for: touch.phase))
  }

  static func fingerValues(for touch: UITouch, in view: UIView) -> PencilSampleValues {
    PencilSampleValues(
      location: touch.location(in: view),
      timeMs: touch.timestamp * 1000,
      pressure: 0,
      altitude: 0,
      azimuth: 0,
      roll: 0,
      hoverHeight: 0,
      has: 0,
      phase: phase(for: touch.phase))
  }

  static func hoverValues(
    location: CGPoint,
    timeMs: Double,
    altitude: CGFloat,
    azimuth: CGFloat,
    roll: CGFloat,
    hoverHeight: CGFloat
  ) -> PencilSampleValues {
    PencilSampleValues(
      location: location,
      timeMs: timeMs,
      pressure: 0,
      altitude: Float(altitude),
      azimuth: Float(azimuth),
      roll: Float(roll),
      hoverHeight: Float(min(max(hoverHeight, 0), 1)),
      has: UInt32(INK_HAS_ALTITUDE) | UInt32(INK_HAS_AZIMUTH) |
        UInt32(INK_HAS_ROLL) | UInt32(INK_HAS_HOVER_HEIGHT),
      phase: UInt8(INK_PHASE_HOVER.rawValue))
  }

  static func batchPhase(
    eventPhase: UITouch.Phase,
    index: Int,
    count: Int
  ) -> UInt8 {
    precondition(count > 0 && index >= 0 && index < count)
    switch eventPhase {
    case .began:
      return UInt8((index == 0 ? INK_PHASE_BEGIN : INK_PHASE_MOVE).rawValue)
    case .ended:
      return UInt8((index == count - 1 ? INK_PHASE_END : INK_PHASE_MOVE).rawValue)
    case .cancelled:
      return UInt8((index == count - 1 ? INK_PHASE_CANCEL : INK_PHASE_MOVE).rawValue)
    case .moved, .stationary:
      return UInt8(INK_PHASE_MOVE.rawValue)
    @unknown default:
      return UInt8(INK_PHASE_CANCEL.rawValue)
    }
  }

  private static func phase(for phase: UITouch.Phase) -> UInt8 {
    switch phase {
    case .began:
      UInt8(INK_PHASE_BEGIN.rawValue)
    case .moved, .stationary:
      UInt8(INK_PHASE_MOVE.rawValue)
    case .ended:
      UInt8(INK_PHASE_END.rawValue)
    case .cancelled:
      UInt8(INK_PHASE_CANCEL.rawValue)
    @unknown default:
      UInt8(INK_PHASE_CANCEL.rawValue)
    }
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
    sample.hover_height = values.hoverHeight
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

  mutating func estimatedUpdate(
    values: PencilSampleValues,
    estimationIndex: NSNumber?,
    finished: Bool
  ) -> InkPenSample? {
    guard let id = updateID(estimationIndex: estimationIndex) else { return nil }
    let sample = PencilSampleFactory.make(values: values, id: id, predicted: false)
    if finished { finish(estimationIndex: estimationIndex) }
    return sample
  }

  mutating func finish(estimationIndex: NSNumber?) {
    guard let estimationIndex else { return }
    estimates.removeValue(forKey: estimationIndex.intValue)
  }
}
