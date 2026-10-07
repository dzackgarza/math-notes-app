import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum PDFImportError: LocalizedError {
  case cannotOpen
  case encrypted
  case empty
  case missingPage(Int)
  case invalidPageSize(Int)
  case rasterizationFailed(Int)

  var errorDescription: String? {
    switch self {
    case .cannotOpen:
      return "The selected PDF could not be opened."
    case .encrypted:
      return "Open an unencrypted PDF to import it."
    case .empty:
      return "The PDF has no pages."
    case let .missingPage(index):
      return "PDF page \(index + 1) could not be read."
    case let .invalidPageSize(index):
      return "PDF page \(index + 1) has an invalid size."
    case let .rasterizationFailed(index):
      return "PDF page \(index + 1) could not be rasterized."
    }
  }
}

struct RasterizedPDFPage {
  let png: Data
  let widthPt: Double
  let heightPt: Double
}

final class PDFImportDocument {
  private let document: PDFDocument
  let pageCount: Int

  init(url: URL) throws {
    guard let data = try? Data(contentsOf: url),
      let document = PDFDocument(data: data)
    else {
      throw PDFImportError.cannotOpen
    }
    guard !document.isLocked else {
      throw PDFImportError.encrypted
    }
    guard document.pageCount > 0 else {
      throw PDFImportError.empty
    }
    self.document = document
    pageCount = document.pageCount
  }

  func rasterizedPage(
    at index: Int,
    maxWidthPixels: CGFloat = 4128
  ) throws -> RasterizedPDFPage {
    guard let page = document.page(at: index) else {
      throw PDFImportError.missingPage(index)
    }

    var size = page.bounds(for: .cropBox).size
    let rotation = ((page.rotation % 360) + 360) % 360
    if rotation == 90 || rotation == 270 {
      size = CGSize(width: size.height, height: size.width)
    }
    guard size.width.isFinite, size.height.isFinite,
      size.width > 0, size.height > 0,
      maxWidthPixels.isFinite, maxWidthPixels > 0
    else {
      throw PDFImportError.invalidPageSize(index)
    }

    let scale = maxWidthPixels / size.width
    let targetSize = CGSize(
      width: maxWidthPixels,
      height: size.height * scale)
    guard targetSize.width.isFinite, targetSize.height.isFinite,
      targetSize.height > 0
    else {
      throw PDFImportError.invalidPageSize(index)
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    let image = renderer.image { context in
      let cg = context.cgContext
      cg.setFillColor(UIColor.white.cgColor)
      cg.fill(CGRect(origin: .zero, size: targetSize))
      cg.saveGState()
      cg.scaleBy(x: scale, y: scale)
      cg.translateBy(x: 0, y: size.height)
      cg.scaleBy(x: 1, y: -1)
      page.draw(with: .cropBox, to: cg)
      cg.restoreGState()
    }
    guard let png = image.pngData() else {
      throw PDFImportError.rasterizationFailed(index)
    }
    return RasterizedPDFPage(
      png: png,
      widthPt: Double(size.width),
      heightPt: Double(size.height))
  }
}

struct PDFImportPicker: UIViewControllerRepresentable {
  let onPick: (URL) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onPick: onPick, onCancel: onCancel)
  }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.pdf],
      asCopy: true)
    picker.allowsMultipleSelection = false
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
