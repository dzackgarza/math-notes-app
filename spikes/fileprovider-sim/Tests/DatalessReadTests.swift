import FileProvider
import XCTest

// Answers one question: in a CI simulator, does a coordinated Data(contentsOf:)
// read of a dataless File Provider item block until the extension's fetch completes?
final class DatalessReadTests: XCTestCase {
  func testCoordinatedReadOfDatalessItemWaitsForFetch() async throws {
    let domain = NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("fpspike"), displayName: "FPSpike")
    try await NSFileProviderManager.add(domain)
    let manager = try XCTUnwrap(NSFileProviderManager(for: domain))
    let root = try await manager.getUserVisibleURL(for: .rootContainer)
    print("FPSpike root", root.path)

    let file = root.appendingPathComponent("notes.json")
    print("FPSpike listing", try FileManager.default.contentsOfDirectory(atPath: root.path))
    let start = Date()
    let finished = expectation(description: "coordinated read returned")
    var readResult: Result<Data, Error>?
    DispatchQueue.global().async {
      var coordinationError: NSError?
      NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
        readResult = Result { try Data(contentsOf: url) }
      }
      if let coordinationError { readResult = .failure(coordinationError) }
      print("FPSpike coordinated read took", Date().timeIntervalSince(start), "s")
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 60)
    let data = try XCTUnwrap(readResult).get()
    XCTAssertEqual(data, Data("{\"fetched\":true}\n".utf8))
    XCTAssertGreaterThan(Date().timeIntervalSince(start), 15, "the read returned before the 20 s fetch finished")
  }
}
