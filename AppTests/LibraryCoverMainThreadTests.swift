import InkEngine
import SwiftUI
import UIKit
import XCTest
@testable import MathNotes

// The 0.1.293 watchdog reports (docs/reports/device-logs) show the main thread
// waiting inside a coordinated read under NotesRootAccess.thumbnail, called from
// LibraryNotebookCover's task, while Dropbox supplied a page on demand. A
// coordinated write held on the notebook folder makes the thumbnail's coordinated
// read of that folder wait the same way.
@MainActor
final class LibraryCoverMainThreadTests: XCTestCase {
  func testCoverThumbnailKeepsMainThreadResponsiveWhileItsPageReadWaits() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = NotesRootAccess(testURL: directory)
    let folder = try root.createFolder(parent: FolderReference(path: []), name: "Dropbox")
    _ = try root.createNote(
      title: "Lecture",
      parent: folder,
      template: "blank",
      pageSize: INK_PAGE_A4,
      orientation: INK_PORTRAIT)
    let listing = try root.library(
      in: FolderReference(path: []), overview: true, sort: .name, direction: .ascending)
    let item = try XCTUnwrap(listing.folders.first { $0.reference.path == folder.path })
    XCTAssertNotNil(item.coverNote)

    // The watchdog stack shows the coordinated read of the notebook folder waiting.
    let notebook = directory.appendingPathComponent("Dropbox/Lecture", isDirectory: true)
    let hold = CoordinatedWriteHold(on: notebook, for: 3)

    // The cover's .task: a main-actor task that asks the root for the thumbnail.
    let cover = try XCTUnwrap(item.coverNote)
    let outcome = ThumbnailOutcome()
    let heartbeat = MainThreadHeartbeat()
    let started = ProcessInfo.processInfo.systemUptime
    Task { @MainActor in
      defer { outcome.seconds = ProcessInfo.processInfo.systemUptime - started }
      do {
        outcome.result = .success(try await root.thumbnail(cover))
      } catch {
        outcome.result = .failure(error)
      }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    heartbeat.stop()

    XCTAssertNotNil(try XCTUnwrap(outcome.result, "the thumbnail never finished").get())
    try hold.check()
    XCTAssertGreaterThanOrEqual(outcome.seconds, 2.5, "the thumbnail did not wait for the held notebook folder")
    XCTAssertLessThan(
      heartbeat.longestGap, 0.5,
      "the main thread stalled \(heartbeat.longestGap) s while the thumbnail waited on its page file")
  }
}

@MainActor
final class ThumbnailOutcome {
  var result: Result<Data?, Error>?
  var seconds: TimeInterval = 0
}

// Records the longest interval between main-run-loop timer ticks.
@MainActor
final class MainThreadHeartbeat {
  private var timer: Timer?
  private var last = ProcessInfo.processInfo.systemUptime
  private(set) var longestGap: TimeInterval = 0

  init() {
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.beat() }
    }
  }

  private func beat() {
    let now = ProcessInfo.processInfo.systemUptime
    longestGap = max(longestGap, now - last)
    last = now
  }

  func stop() {
    beat()
    timer?.invalidate()
  }
}

// Holds a coordinated write on a file from a background thread, as a file
// provider holds an item while it downloads; coordinated readers wait until the
// hold ends. Spins the main run loop until the hold starts, because the notes
// root's file presenter answers coordination on the main queue.
@MainActor
final class CoordinatedWriteHold {
  private let state = HoldState()

  init(on file: URL, for duration: TimeInterval) {
    let state = self.state
    Thread.detachNewThread {
      var error: NSError?
      NSFileCoordinator().coordinate(writingItemAt: file, options: [], error: &error) { _ in
        state.set(.holding)
        Thread.sleep(forTimeInterval: duration)
      }
      state.set(error.map { .failed($0) } ?? .released)
    }
    while state.get() == .waiting {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }

  func check() throws {
    if case let .failed(error) = state.get() { throw error }
  }
}

final class HoldState: @unchecked Sendable {
  enum Phase: Equatable { case waiting, holding, released, failed(NSError) }
  private let lock = NSLock()
  private var phase = Phase.waiting
  func get() -> Phase { lock.withLock { phase } }
  func set(_ next: Phase) { lock.withLock { phase = next } }
}
