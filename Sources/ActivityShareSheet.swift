import SwiftUI
import UIKit

struct SharePayload: Identifiable {
  let url: URL

  var id: URL { url }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ExportPayload: Identifiable {
  let url: URL

  var id: URL { url }
}

struct DocumentExportPicker: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    UIDocumentPickerViewController(forExporting: [url], asCopy: true)
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
