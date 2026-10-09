import Foundation
import SwiftUI
import UIKit
import WebKit
import os

struct FigureEditorRequest: Identifiable {
  let id: String
  let source: String
  let viewID: UUID
}

private struct FigureEditorMessage: Decodable {
  let event: String?
  let source: String?
  let error: String?
}

// Builds the figure editor's web view and message bridge and loads the bundled
// editor. The sheet and its tests load the editor through this one path.
@MainActor
enum FigureEditorPage {
  // How long the editor may take to start before the sheet reports that it
  // did not. A cold start launches WebKit's GPU, networking and content
  // processes first.
  static let startLimit: Duration = .seconds(20)

  static func makeWebView(handler: WKScriptMessageHandler) throws -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    // Forwards the editor's protocol messages, and reports the page's own
    // errors to the app log so a failed start is never silent.
    let bridge = """
      const report = (text) => window.webkit.messageHandlers.mathNotesFigureLog.postMessage(String(text));
      window.addEventListener('error', (event) => report('error: ' + event.message + ' at ' + event.filename + ':' + event.lineno));
      // A module script or stylesheet that fails to load fires 'error' on its
      // element, which reaches window only in the capture phase.
      window.addEventListener('error', (event) => {
        if (event.target !== window) report('resource failed to load: ' + (event.target.src || event.target.href));
      }, true);
      document.addEventListener('DOMContentLoaded', () => report('lifecycle: DOMContentLoaded'));
      window.addEventListener('load', () => report('lifecycle: load'));
      window.addEventListener('unhandledrejection', (event) => report('unhandled rejection: ' + event.reason));
      const consoleError = console.error;
      console.error = (...args) => { report('console.error: ' + args.join(' ')); consoleError(...args); };
      window.addEventListener('message', function(event) {
        if (typeof event.data !== 'string') return;
        let message;
        try {
          message = JSON.parse(event.data);
        } catch (error) {
          report('unparsable message: ' + event.data);
          return;
        }
        if (message && typeof message.event === 'string') {
          window.webkit.messageHandlers.mathNotesFigure.postMessage(event.data);
        }
      });
      """
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: bridge,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true))
    configuration.userContentController.add(handler, name: "mathNotesFigure")
    configuration.userContentController.add(handler, name: "mathNotesFigureLog")

    guard let root = Bundle.main.url(forResource: "TikZEditor", withExtension: nil) else {
      throw NSError(
        domain: "MathNotes.FigureEditor",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing bundled TikZ editor."])
    }
    configuration.setURLSchemeHandler(
      BundledEditorSchemeHandler(root: root), forURLScheme: BundledEditorSchemeHandler.scheme)

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.load(URLRequest(url: BundledEditorSchemeHandler.indexURL))
    return webView
  }
}

// Serves the bundled TikZ editor from one origin, mathnotes://tikz-editor/.
// Loaded from file:// the page has origin null, and WebKit rejects its
// crossorigin module scripts and stylesheets, so the editor never starts. The
// recorded decision (docs/research_notes/Component ownership decisions/tikz.md)
// and Capacitor's WebViewAssetHandler serve app bundles this way.
final class BundledEditorSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "mathnotes"
  static let host = "tikz-editor"
  static let indexURL = URL(string: "\(scheme)://\(host)/index.html")!

  // The editor bundle holds only these file types (hosts/web/build-tikz.mjs).
  private static let contentTypes = [
    "html": "text/html; charset=utf-8",
    "js": "text/javascript; charset=utf-8",
    "css": "text/css; charset=utf-8",
    "woff2": "font/woff2",
  ]

  private let root: URL

  init(root: URL) {
    self.root = root.standardizedFileURL
  }

  func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
    do {
      let (url, data, contentType) = try resource(for: task.request)
      Log.app.info("figure editor resource \(url.path, privacy: .public) served \(data.count, privacy: .public) bytes")
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType, "Content-Length": String(data.count)])!
      task.didReceive(response)
      task.didReceive(data)
      task.didFinish()
    } catch {
      Log.app.error("figure editor resource \(task.request.url?.absoluteString ?? "none", privacy: .public) failed: \(String(describing: error), privacy: .public)")
      task.didFailWithError(error)
    }
  }

  func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

  private func resource(for request: URLRequest) throws -> (URL, Data, String) {
    guard let url = request.url, url.host == Self.host else {
      throw URLError(.unsupportedURL)
    }
    let file = root.appendingPathComponent(String(url.path.dropFirst())).standardizedFileURL
    guard file.path.hasPrefix(root.path + "/") else {
      throw URLError(.noPermissionsToReadFile)
    }
    guard let contentType = Self.contentTypes[file.pathExtension] else {
      throw NSError(
        domain: "MathNotes.FigureEditor",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "The figure editor requested an unsupported file type: \(file.lastPathComponent)"])
    }
    return (url, try Data(contentsOf: file), contentType)
  }
}

@MainActor
private struct FigureEditorWebView: UIViewRepresentable {
  let initialSource: String
  let saveRevision: Int
  let onEvent: (FigureEditorMessage) -> Void
  let onError: (Error) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      initialSource: initialSource,
      onEvent: onEvent,
      onError: onError)
  }

  func makeUIView(context: Context) -> WKWebView {
    do {
      let webView = try FigureEditorPage.makeWebView(handler: context.coordinator)
      context.coordinator.webView = webView
      webView.navigationDelegate = context.coordinator
      return webView
    } catch {
      onError(error)
      return WKWebView(frame: .zero)
    }
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    context.coordinator.onEvent = onEvent
    context.coordinator.onError = onError
    if saveRevision != context.coordinator.saveRevision {
      context.coordinator.saveRevision = saveRevision
      context.coordinator.requestSave()
    }
  }

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "mathNotesFigure")
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "mathNotesFigureLog")
    webView.navigationDelegate = nil
    coordinator.webView = nil
  }

  @MainActor
  final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      ready = false
      onError(NSError(
        domain: "MathNotes.FigureEditor",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "The figure editor stopped responding. Close and reopen it."]))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      Log.app.info("figure editor page loaded")
      Task { @MainActor [weak self] in
        try await Task.sleep(for: FigureEditorPage.startLimit)
        guard let self, self.webView != nil, !self.ready else { return }
        Log.app.fault("figure editor sent no 'loaded' message within \(FigureEditorPage.startLimit, privacy: .public) of its page loading")
        self.onError(NSError(
          domain: "MathNotes.FigureEditor",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "The figure editor did not start. Close it and try again."]))
      }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      Log.app.error("figure editor navigation failed: \(String(describing: error), privacy: .public)")
      onError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      Log.app.error("figure editor page failed to load: \(String(describing: error), privacy: .public)")
      onError(error)
    }

    let initialSource: String
    var onEvent: (FigureEditorMessage) -> Void
    var onError: (Error) -> Void
    weak var webView: WKWebView?
    var ready = false
    var pendingSave = false
    var saveRevision = 0

    init(
      initialSource: String,
      onEvent: @escaping (FigureEditorMessage) -> Void,
      onError: @escaping (Error) -> Void
    ) {
      self.initialSource = initialSource
      self.onEvent = onEvent
      self.onError = onError
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let raw = message.body as? String else { return }
      if message.name == "mathNotesFigureLog" {
        Log.app.notice("figure editor page \(raw, privacy: .public)")
        return
      }
      Log.app.info("figure editor message \(String(raw.prefix(80)), privacy: .public)")
      do {
        let decoded = try JSONDecoder().decode(
          FigureEditorMessage.self,
          from: Data(raw.utf8))
        if decoded.event == "init" {
          send([
            "action": "load",
            "source": initialSource,
            "autosave": 1,
            "fileName": "figure.tikz",
          ])
          return
        }
        if decoded.event == "loaded" {
          ready = true
          if pendingSave {
            pendingSave = false
            requestSave()
          }
        } else if !ready {
          return
        }
        onEvent(decoded)
      } catch {
        onError(error)
      }
    }

    func requestSave() {
      guard ready else {
        pendingSave = true
        return
      }
      send(["action": "save"])
    }

    private func send(_ payload: [String: Any]) {
      guard let webView else { return }
      do {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else { return }
        let literalData = try JSONEncoder().encode(json)
        guard let literal = String(data: literalData, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.postMessage(\(literal), '*')") { [onError] _, error in
          if let error { onError(error) }
        }
      } catch {
        onError(error)
      }
    }
  }
}

@MainActor
struct FigureEditorSheet: View {
  let request: FigureEditorRequest
  let onDraft: (String, Bool) throws -> Void
  let onDismiss: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var source: String
  @State private var ready = false
  @State private var closing = false
  @State private var saveRevision = 0
  @State private var errorMessage: String?

  init(
    request: FigureEditorRequest,
    onDraft: @escaping (String, Bool) throws -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.request = request
    self.onDraft = onDraft
    self.onDismiss = onDismiss
    _source = State(initialValue: request.source)
  }

  var body: some View {
    NavigationStack {
      FigureEditorWebView(
        initialSource: request.source,
        saveRevision: saveRevision,
        onEvent: accept,
        onError: { error in
          errorMessage = error.localizedDescription
          closing = false
          let failure = error as NSError
          if failure.domain == "MathNotes.FigureEditor" && failure.code == 2 {
            ready = false
          }
        })
        .overlay {
          if !ready {
            ProgressView("Loading figure editor…")
              .padding(16)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          }
        }
        .nativePageSurface()
        .navigationTitle("Figure editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            if !ready {
              Button("Close") { dismiss() }
            }
          }
          ToolbarItem(placement: .topBarLeading) {
            Button("Copy TikZ", systemImage: "doc.on.doc") {
              UIPasteboard.general.string = source
            }
            .disabled(source.isEmpty)
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button(closing ? "Saving…" : "Save and close", action: requestClose)
              .disabled(closing || !ready)
              .accessibilityIdentifier("figure-editor-save")
          }
        }
        .safeAreaInset(edge: .bottom) {
          if let errorMessage {
            Text(errorMessage)
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
              .background(.regularMaterial)
          }
        }
    }
    .interactiveDismissDisabled(true)
    .background {
      CreationDismissGuard(onAttempt: requestClose)
        .frame(width: 0, height: 0)
    }
    .onDisappear(perform: onDismiss)
  }

  private func requestClose() {
    guard ready, !closing else { return }
    closing = true
    saveRevision &+= 1
  }

  private func accept(_ message: FigureEditorMessage) {
    if message.event == "loaded" {
      ready = true
    }
    if let messageError = message.error, !messageError.isEmpty {
      errorMessage = messageError
      closing = false
      return
    }
    guard let nextSource = message.source,
      ["change", "autosave", "save"].contains(message.event ?? "")
    else { return }

    source = nextSource
    do {
      let persistent = message.event == "save"
      try onDraft(nextSource, persistent)
      errorMessage = nil
      if message.event == "save", closing {
        dismiss()
      }
    } catch {
      errorMessage = error.localizedDescription
      closing = false
    }
  }
}
