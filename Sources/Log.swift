import Foundation
import os

// App-owned log. Read on the device with idevicesyslog or Console, filtered by
// subsystem dev.zack.mathnotes. Every dropped input, failed engine call, and
// file operation is recorded here; nothing on these paths fails silently.
enum Log {
  static let ink = Logger(subsystem: "dev.zack.mathnotes", category: "ink")
  static let storage = Logger(subsystem: "dev.zack.mathnotes", category: "storage")
  static let app = Logger(subsystem: "dev.zack.mathnotes", category: "app")
  static let engine = Logger(subsystem: "dev.zack.mathnotes", category: "engine")

  // Main-thread work longer than this is logged as a fault: the watchdog kills
  // the app when the main thread stays blocked.
  static let mainThreadBudget: Duration = .milliseconds(100)
}

extension Duration {
  var milliseconds: Double {
    Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
  }
}
