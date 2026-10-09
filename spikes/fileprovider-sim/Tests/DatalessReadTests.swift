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
    let start = Date()
    var coordinationError: NSError?
    var readResult: Result<Data, Error>?
    NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
      readResult = Result { try Data(contentsOf: url) }
    }
    let elapsed = Date().timeIntervalSince(start)
    print("FPSpike coordinated read took", elapsed, "s")
    if let coordinationError { throw coordinationError }
    let data = try XCTUnwrap(readResult).get()
    XCTAssertEqual(data, Data("{\"fetched\":true}\n".utf8))
    XCTAssertGreaterThan(elapsed, 15, "the read returned before the 20 s fetch finished")
  }
}
