import Foundation
import SwiftUI
import UIKit
import WebKit

struct FigureEditorRequest: Identifiable {
  let id: String
  let source: String
}

private struct FigureEditorMessage: Decodable {
  let event: String?
  let source: String?
  let error: String?
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
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    let bridge = """
      window.addEventListener('message', function(event) {
        if (typeof event.data !== 'string') return;
        try {
          const message = JSON.parse(event.data);
          if (message && typeof message.event === 'string') {
            window.webkit.messageHandlers.mathNotesFigure.postMessage(event.data);
          }
        } catch (_) {}
      });
      """
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: bridge,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true))
    configuration.userContentController.add(context.coordinator, name: "mathNotesFigure")

    let webView = WKWebView(frame: .zero, configuration: configuration)
    context.coordinator.webView = webView

    guard let index = Bundle.main.url(
      forResource: "index",
      withExtension: "html",
      subdirectory: "TikZEditor")
    else {
      onError(
        NSError(
          domain: "MathNotes.FigureEditor",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Missing bundled TikZ editor."]))
      return webView
    }
    webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
    return webView
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
    coordinator.webView = nil
  }

  @MainActor
  final class Coordinator: NSObject, WKScriptMessageHandler {
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
  @Environment(\.dismiss) private var dismiss
  @State private var source: String
  @State private var ready = false
  @State private var closing = false
  @State private var saveRevision = 0
  @State private var errorMessage: String?

  init(
    request: FigureEditorRequest,
    onDraft: @escaping (String, Bool) throws -> Void
  ) {
    self.request = request
    self.onDraft = onDraft
    _source = State(initialValue: request.source)
  }

  var body: some View {
    NavigationStack {
      FigureEditorWebView(
        initialSource: request.source,
        saveRevision: saveRevision,
        onEvent: accept,
        onError: { errorMessage = $0.localizedDescription })
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
          ToolbarItem(placement: .topBarLeading) {
            Button("Copy TikZ", systemImage: "doc.on.doc") {
              UIPasteboard.general.string = source
            }
            .disabled(source.isEmpty)
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button(closing ? "Saving…" : "Save and close") {
              if ready {
                closing = true
                saveRevision &+= 1
              } else {
                dismiss()
              }
            }
            .disabled(closing)
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
  }

  private func accept(_ message: FigureEditorMessage) {
    if message.event == "loaded" {
      ready = true
    }
    if let messageError = message.error, !messageError.isEmpty {
      errorMessage = messageError
    }
    guard let nextSource = message.source,
      ["change", "autosave", "save"].contains(message.event ?? "")
    else { return }

    source = nextSource
    do {
      let persistent = message.event == "autosave" || message.event == "save"
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
