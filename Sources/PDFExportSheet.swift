import Foundation
import SwiftUI

struct PDFExportRequest: Identifiable {
  let id = UUID()
  let pageCount: Int
  let currentPage: Int
  let layers: [EngineLayer]
}

private enum PDFExportScope: String, CaseIterable, Identifiable {
  case all = "All Pages"
  case range = "Page Range"

  var id: Self { self }
}

struct PDFExportSheet: View {
  let request: PDFExportRequest
  let onExport: (Int, Int, [String]) -> Void
  let onCancel: () -> Void

  @State private var scope: PDFExportScope = .all
  @State private var firstPage: Int
  @State private var lastPage: Int
  @State private var includedLayers: Set<String>

  init(
    request: PDFExportRequest,
    onExport: @escaping (Int, Int, [String]) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.request = request
    self.onExport = onExport
    self.onCancel = onCancel
    let current = min(max(request.currentPage + 1, 1), max(request.pageCount, 1))
    _firstPage = State(initialValue: current)
    _lastPage = State(initialValue: current)
    _includedLayers = State(
      initialValue: Set(request.layers.filter { !$0.hidden }.map(\.id)))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Pages") {
          Picker("Export", selection: $scope) {
            ForEach(PDFExportScope.allCases) { item in
              Text(item.rawValue).tag(item)
            }
          }
          .pickerStyle(.segmented)

          if scope == .range {
            Stepper(
              "From page \(firstPage)",
              value: $firstPage,
              in: 1...max(1, lastPage))

            Stepper(
              "Through page \(lastPage)",
              value: $lastPage,
              in: min(firstPage, max(1, request.pageCount))...max(1, request.pageCount))
          } else {
            LabeledContent("Page count", value: "\(request.pageCount)")
          }
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
      .navigationTitle("Export PDF")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Export") {
            let layers = request.layers
              .filter { includedLayers.contains($0.id) }
              .map(\.id)
            if scope == .all {
              onExport(0, request.pageCount, layers)
            } else {
              onExport(firstPage - 1, lastPage - firstPage + 1, layers)
            }
          }
          .disabled(request.pageCount <= 0)
        }
      }
    }
  }
}
