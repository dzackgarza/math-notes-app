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
  let onSave: (String) async -> Bool
  let onMove: (String, Int) async -> Bool
  let onDelete: (String) async -> Bool
  let onRefresh: () async -> [ClippingPreview]?
  let onClose: () -> Void

  @State private var items: [ClippingPreview]
  @State private var dropTargeted = false
  @State private var dropSession = UUID()

  init(
    request: ClippingsRequest,
    selectionActive: Bool,
    drawing: Bool,
    onInsert: @escaping (String) -> Void,
    onSaveSelection: @escaping () -> Void,
    onSave: @escaping (String) async -> Bool,
    onMove: @escaping (String, Int) async -> Bool,
    onDelete: @escaping (String) async -> Bool,
    onRefresh: @escaping () async -> [ClippingPreview]?,
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
          VStack(spacing: 8) {
            Button {
              onInsert(item.id)
            } label: {
              if let image = UIImage(data: item.png) {
                Image(uiImage: image)
                  .resizable()
                  .scaledToFit()
                  .frame(maxWidth: .infinity)
              } else {
                Image(systemName: "doc")
                  .frame(maxWidth: .infinity)
                  .frame(minHeight: 44)
              }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(!availability.canInsert)
            .onDrag {
              let provider = NSItemProvider()
              provider.registerDataRepresentation(
                forTypeIdentifier: notebookClippingDragType.identifier,
                visibility: .ownProcess
              ) { completion in
                completion(Data(item.id.utf8), nil)
                return nil
              }
              return provider
            }
            .allowsHitTesting(availability.canInsert)
            .accessibilityLabel("Insert clipping \(item.index + 1)")

            HStack(spacing: 8) {
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
          .frame(maxWidth: .infinity)
        }
      }
      .scrollContentBackground(.hidden)
      .nativePageSurface()
      .navigationTitle("Clippings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            Task {
              if let refreshed = await onRefresh() {
                items = refreshed
              }
            }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel("Refresh")

          Button(action: onClose) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Close clippings")
        }
      }
    }
    .frame(width: 240)
    .onAppear { dropSession = UUID() }
    .onDisappear { dropSession = UUID() }
    .onDrop(
      of: [notebookSelectionCopyDragType],
      isTargeted: $dropTargeted
    ) { providers in
      guard availability.canAcceptDrop,
        let provider = providers.first(where: {
          $0.hasItemConformingToTypeIdentifier(notebookSelectionCopyDragType.identifier)
        }) else {
        return false
      }
      let session = dropSession
      provider.loadDataRepresentation(
        forTypeIdentifier: notebookSelectionCopyDragType.identifier
      ) { data, _ in
        guard let data, let svg = String(data: data, encoding: .utf8),
          svg.contains("<svg")
        else { return }
        Task { @MainActor in
          guard session == dropSession else { return }
          guard ClippingsPanelAvailability(
            selectionActive: selectionActive, drawing: drawing
          ).canAcceptDrop else { return }
          guard await onSave(svg) else { return }
          if let refreshed = await onRefresh() { items = refreshed }
        }
      }
      return true
    }
    .background(
      dropTargeted && availability.canAcceptDrop
        ? NativeTheme.selectedFill
        : NativeTheme.board)
  }

  private func move(_ item: ClippingPreview, by offset: Int) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    let target = index + offset
    guard target >= 0, target < items.count else { return }
    Task {
      guard await onMove(item.id, offset) else { return }
      if let refreshed = await onRefresh() { items = refreshed }
    }
  }

  private func remove(_ item: ClippingPreview) {
    guard items.contains(where: { $0.id == item.id }) else { return }
    Task {
      guard await onDelete(item.id) else { return }
      if let refreshed = await onRefresh() { items = refreshed }
    }
  }
}
