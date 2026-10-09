import Darwin
import InkEngine
import SwiftUI
import UIKit
import XCTest
@testable import MathNotes

// The 0.1.293 watchdog reports (docs/reports/device-logs) show the main thread
// blocked in read() under NotesRootAccess.thumbnail, called from
// LibraryNotebookCover's task, while Dropbox downloaded a page on demand. A
// FIFO in place of the page file blocks read() the same way until its writer
// delivers the bytes.
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

    let page = directory.appendingPathComponent("Dropbox/Lecture/pages/0001.svg")
    let server = try SlowFileServer(replacing: page, delay: 3)
    defer { server.stop() }

    // The cover's .task: a main-actor task that asks the root for the thumbnail.
    let cover = try XCTUnwrap(item.coverNote)
    let outcome = ThumbnailOutcome()
    let heartbeat = MainThreadHeartbeat()
    Task { @MainActor in
      do {
        outcome.result = .success(try await root.thumbnail(cover))
      } catch {
        outcome.result = .failure(error)
      }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    heartbeat.stop()

    XCTAssertNotNil(try XCTUnwrap(outcome.result, "the thumbnail never finished").get())
    XCTAssertGreaterThan(server.servedReads, 0, "the thumbnail never read the page file")
    XCTAssertLessThan(
      heartbeat.longestGap, 0.5,
      "the main thread stalled \(heartbeat.longestGap) s while the thumbnail waited on its page file")
  }
}

@MainActor
final class ThumbnailOutcome {
  var result: Result<Data?, Error>?
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

// Replaces a file with a FIFO. Each time a reader opens it, the server waits
// `delay` seconds before writing the original bytes, as an on-demand download does.
final class SlowFileServer: @unchecked Sendable {
  private let path: String
  private let bytes: Data
  private let delay: TimeInterval
  private let lock = NSLock()
  private var stopped = false
  private var reads = 0

  var servedReads: Int { lock.withLock { reads } }

  init(replacing file: URL, delay: TimeInterval) throws {
    path = file.path
    bytes = try Data(contentsOf: file)
    self.delay = delay
    try FileManager.default.removeItem(at: file)
    // A reader that closes early must surface as EPIPE, not kill the test process.
    signal(SIGPIPE, SIG_IGN)
    guard mkfifo(path, 0o644) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    Thread.detachNewThread { [self] in serve() }
  }

  private func serve() {
    while true {
      let fd = open(path, O_WRONLY)
      if lock.withLock({ stopped }) {
        if fd >= 0 { close(fd) }
        return
      }
      precondition(fd >= 0, "open FIFO for writing failed: \(errno)")
      Thread.sleep(forTimeInterval: delay)
      let written = bytes.withUnsafeBytes { raw in write(fd, raw.baseAddress, raw.count) }
      close(fd)
      precondition(written == bytes.count || errno == EPIPE, "FIFO write failed: \(errno)")
      if written == bytes.count { lock.withLock { reads += 1 } }
    }
  }

  // Opens and closes the reading end so a writer waiting in open() returns and exits.
  func stop() {
    lock.withLock { stopped = true }
    let fd = open(path, O_RDONLY | O_NONBLOCK)
    if fd >= 0 { close(fd) }
  }
}
