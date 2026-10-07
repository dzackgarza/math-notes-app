import Foundation
import SwiftUI
import UIKit

func removeExportTemporaryFile(_ url: URL) {
  try? FileManager.default.removeItem(at: url)
}

struct SharePayload: Identifiable {
  let url: URL

  var id: URL { url }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator { Coordinator(url: url) }

  final class Coordinator {
    let url: URL
    init(url: URL) { self.url = url }
  }

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.completionWithItemsHandler = { _, _, _, _ in
      removeExportTemporaryFile(url)
    }
    return controller
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

  static func dismantleUIViewController(_ uiViewController: UIActivityViewController, coordinator: Coordinator) {
    removeExportTemporaryFile(coordinator.url)
  }
}

struct ExportPayload: Identifiable {
  let url: URL

  var id: URL { url }
}

struct DocumentExportPicker: UIViewControllerRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

  static func dismantleUIViewController(_ uiViewController: UIDocumentPickerViewController, coordinator: Coordinator) {
    removeExportTemporaryFile(coordinator.url)
  }

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let url: URL

    init(url: URL) {
      self.url = url
    }

    func documentPicker(
      _ controller: UIDocumentPickerViewController,
      didPickDocumentsAt urls: [URL]
    ) {
      removeExportTemporaryFile(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      removeExportTemporaryFile(url)
    }
  }
}
