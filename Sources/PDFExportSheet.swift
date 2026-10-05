import Foundation
import SwiftUI

enum PDFExportDestination: Equatable {
  case share
  case export

  var menuLabel: String {
    switch self {
    case .share: "Share"
    case .export: "Export PDF"
    }
  }

  var title: String {
    switch self {
    case .share: "Share PDF"
    case .export: "Export PDF"
    }
  }

  var actionLabel: String {
    switch self {
    case .share: "Share"
    case .export: "Export"
    }
  }
}

struct PDFExportRequest: Identifiable {
  let id = UUID()
  let sessionID: UUID
  let destination: PDFExportDestination
  let pageCount: Int
  let currentPage: Int
  let layers: [EngineLayer]
}

struct PDFExportSheet: View {
  let request: PDFExportRequest
  let onExport: (Int, Int, [String]) -> Void
  let onCancel: () -> Void

  @State private var firstPage: String
  @State private var lastPage: String
  @State private var includedLayers: Set<String>

  init(
    request: PDFExportRequest,
    onExport: @escaping (Int, Int, [String]) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.request = request
    self.onExport = onExport
    self.onCancel = onCancel
    _firstPage = State(initialValue: "1")
    _lastPage = State(initialValue: String(max(request.pageCount, 1)))
    _includedLayers = State(
      initialValue: Set(request.layers.filter { !$0.hidden }.map(\.id)))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Pages") {
          TextField("First page", text: $firstPage)
            .keyboardType(.numberPad)
            .nativeFieldSurface()
          TextField("Last page", text: $lastPage)
            .keyboardType(.numberPad)
            .nativeFieldSurface()
        }

        Section("Layers") {
          ForEach(request.layers) { layer in
            Toggle(
              layer.name,
              isOn: Binding(
                get: { includedLayers.contains(layer.id) },
                set: { included in
                  if included {
                    includedLayers.insert(layer.id)
                  } else {
                    includedLayers.remove(layer.id)
                  }
                }))
          }
        }
      }
      .scrollContentBackground(.hidden)
      .nativeSheetSurface()
      .navigationTitle(request.destination.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(request.destination.actionLabel) {
            guard let range = pageRange else { return }
            let layers = request.layers
              .filter { includedLayers.contains($0.id) }
              .map(\.id)
            onExport(range.first - 1, range.last - range.first + 1, layers)
          }
          .disabled(pageRange == nil)
        }
      }
    }
  }
  private var pageRange: (first: Int, last: Int)? {
    guard let first = Int(firstPage), let last = Int(lastPage),
      first >= 1, last >= first, last <= request.pageCount
    else { return nil }
    return (first, last)
  }

}
