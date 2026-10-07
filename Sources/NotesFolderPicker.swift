import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct NotesFolderPicker: UIViewControllerRepresentable {
  let initialDirectory: URL?
  let onPick: (URL) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onPick: onPick, onCancel: onCancel)
  }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.folder],
      asCopy: false)
    picker.allowsMultipleSelection = false
    picker.directoryURL = initialDirectory
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(
    _ uiViewController: UIDocumentPickerViewController,
    context: Context
  ) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL) -> Void
    private let onCancel: () -> Void

    init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
      self.onPick = onPick
      self.onCancel = onCancel
    }

    func documentPicker(
      _ controller: UIDocumentPickerViewController,
      didPickDocumentsAt urls: [URL]
    ) {
      guard let url = urls.first else {
        onCancel()
        return
      }
      onPick(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      onCancel()
    }
  }
}
