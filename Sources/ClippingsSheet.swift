import Foundation
import SwiftUI
import UIKit

struct ClippingPreview: Identifiable {
  let id: String
  let index: Int
  let png: Data
}

struct ClippingsPanelAvailability: Equatable {
  let selectionActive: Bool
  let drawing: Bool

  var canSaveSelection: Bool { selectionActive && !drawing }
  var canInsert: Bool { !drawing }
  var canAcceptDrop: Bool { !drawing }
}

struct ClippingsRequest: Identifiable {
  let id = UUID()
  let items: [ClippingPreview]
}

struct ClippingsSheet: View {
  let selectionActive: Bool
  let drawing: Bool
  let onInsert: (String) -> Void
  let onSaveSelection: () -> Void
  let onSave: (String) -> Bool
  let onMove: (String, Int) -> Bool
  let onDelete: (String) -> Bool
  let onRefresh: () -> [ClippingPreview]?
  let onClose: () -> Void

  @State private var items: [ClippingPreview]
  @State private var dropTargeted = false

  init(
    request: ClippingsRequest,
    selectionActive: Bool,
    drawing: Bool,
    onInsert: @escaping (String) -> Void,
    onSaveSelection: @escaping () -> Void,
    onSave: @escaping (String) -> Bool,
    onMove: @escaping (String, Int) -> Bool,
    onDelete: @escaping (String) -> Bool,
    onRefresh: @escaping () -> [ClippingPreview]?,
    onClose: @escaping () -> Void
  ) {
    self.selectionActive = selectionActive
    self.drawing = drawing
    self.onInsert = onInsert
    self.onSaveSelection = onSaveSelection
    self.onSave = onSave
    self.onMove = onMove
    self.onDelete = onDelete
    self.onRefresh = onRefresh
    self.onClose = onClose
    _items = State(initialValue: request.items)
  }

  var body: some View {
    let availability = ClippingsPanelAvailability(
      selectionActive: selectionActive,
      drawing: drawing)
    NavigationStack {
      List {
        Section {
          Text("Drop a selection here to save it. Drag a clipping onto the page.")
            .font(NativeTheme.footnote)
            .foregroundStyle(NativeTheme.graphite)
          if availability.canSaveSelection {
            Button("Save selected content", action: onSaveSelection)
          }
        }

        ForEach(items) { item in
          HStack(spacing: 12) {
          Button {
            onInsert(item.id)
          } label: {
            if let image = UIImage(data: item.png) {
              Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 72)
            } else {
              Image(systemName: "doc")
                .frame(width: 120, height: 72)
            }
          }
          .buttonStyle(.plain)
          .disabled(!availability.canInsert)
          .draggable(item.id)
          .accessibilityLabel("Insert clipping \(item.index + 1)")

          Spacer()

          Button {
            move(item, by: -1)
          } label: {
            Image(systemName: "arrow.up")
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .disabled(item.index == 0)
          .accessibilityLabel("Move clipping up")

          Button {
            move(item, by: 1)
          } label: {
            Image(systemName: "arrow.down")
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .disabled(item.index == items.count - 1)
          .accessibilityLabel("Move clipping down")

          Button(role: .destructive) {
            remove(item)
          } label: {
            Image(systemName: "trash")
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .accessibilityLabel("Delete clipping")
          }
        }
      }
      .scrollContentBackground(.hidden)
      .nativePageSurface()
      .navigationTitle("Clippings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            if let refreshed = onRefresh() {
              items = refreshed
            }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onClose)
        }
      }
    }
    .frame(width: 340)
    .dropDestination(
      for: String.self,
      action: { values, _ in
        guard availability.canAcceptDrop,
          let svg = values.first, svg.contains("<svg"), onSave(svg)
        else { return false }
        if let refreshed = onRefresh() { items = refreshed }
        return true
      },
      isTargeted: { dropTargeted = $0 })
    .background(
      dropTargeted && availability.canAcceptDrop
        ? NativeTheme.selectedFill
        : NativeTheme.board)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(radius: 10)
    .padding(8)
  }

  private func move(_ item: ClippingPreview, by offset: Int) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    let target = index + offset
    guard target >= 0, target < items.count, onMove(item.id, offset) else { return }
    if let refreshed = onRefresh() { items = refreshed }
  }

  private func remove(_ item: ClippingPreview) {
    guard items.contains(where: { $0.id == item.id }), onDelete(item.id) else { return }
    if let refreshed = onRefresh() { items = refreshed }
  }
}
