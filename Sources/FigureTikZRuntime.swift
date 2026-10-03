import Foundation
import WebKit

private enum FigureTikZRuntimeError: LocalizedError {
  case missingResource(String)
  case invalidResult

  var errorDescription: String? {
    switch self {
    case let .missingResource(name):
      return "Missing bundled TikZ resource: \(name)"
    case .invalidResult:
      return "FreeTikZ did not return TikZ source."
    }
  }
}

@MainActor
private final class FigureRuntimeNavigation: NSObject, WKNavigationDelegate {
  private var continuation: CheckedContinuation<Void, Error>?

  func load(_ webView: WKWebView, url: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      webView.navigationDelegate = self
      webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    continuation?.resume()
    continuation = nil
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    continuation?.resume(throwing: error)
    continuation = nil
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    continuation?.resume(throwing: error)
    continuation = nil
  }
}

@MainActor
final class FigureTikZGenerator {
  private let webView = WKWebView(frame: .zero)
  private var loadTask: Task<Void, Error>?
  private var loaded = false

  func generate(scene: String) async throws -> (scene: String, source: String) {
    try await ensureLoaded()
    let literalData = try JSONEncoder().encode(scene)
    guard let literal = String(data: literalData, encoding: .utf8) else {
      throw FigureTikZRuntimeError.invalidResult
    }
    let result = try await webView.evaluateJavaScript(
      "window.mathNotesGenerateTikz(\(literal))")
    guard let result = result as? [String: Any],
      let scene = result["scene"] as? String,
      let source = result["source"] as? String,
      !scene.isEmpty,
      !source.isEmpty
    else {
      throw FigureTikZRuntimeError.invalidResult
    }
    return (scene, source)
  }

  private func ensureLoaded() async throws {
    if loaded { return }
    if let loadTask {
      try await loadTask.value
      loaded = true
      self.loadTask = nil
      return
    }
    guard let url = Bundle.main.url(
      forResource: "generator",
      withExtension: "html",
      subdirectory: "TikZRuntime")
    else {
      throw FigureTikZRuntimeError.missingResource("TikZRuntime/generator.html")
    }
    let webView = self.webView
    let task = Task { @MainActor in
      let navigation = FigureRuntimeNavigation()
      try await navigation.load(webView, url: url)
    }
    loadTask = task
    do {
      try await task.value
      loaded = true
      loadTask = nil
    } catch {
      loadTask = nil
      throw error
    }
  }
}
