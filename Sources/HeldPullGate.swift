import Foundation

struct HeldPullGate {
  static let holdDuration: TimeInterval = 0.35

  private var readySince: TimeInterval?

  mutating func becameReady(at time: TimeInterval) {
    if readySince == nil {
      readySince = time
    }
  }

  mutating func leftReady() {
    readySince = nil
  }

  mutating func release(at time: TimeInterval) -> Bool {
    defer { readySince = nil }
    guard let readySince else { return false }
    return time >= readySince + Self.holdDuration
  }
}
