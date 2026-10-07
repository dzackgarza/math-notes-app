import SwiftUI

func layerActionAccessibilityLabel(_ action: String, layerName: String) -> String {
  "\(action) \(layerName)"
}

@MainActor
struct LayersSheet: View {
  let document: EngineDocument
  @Binding var activeLayerID: String?
  let onEdit: () -> Void
  let onError: (Error) -> Void
  let onDone: () -> Void

  @State private var layers: [EngineLayer] = []
  @State private var namingLayerID: String?
  @State private var addingLayer = false
  @State private var layerName = ""
  @State private var deleteLayerID: String?

  var body: some View {
    NavigationStack {
      Form {
        ForEach(Array(layers.indices.reversed()), id: \.self) { index in
          let layer = layers[index]
          Section {
            HStack(spacing: 8) {
              Button {
                guard !layer.hidden, !layer.locked else { return }
                activeLayerID = layer.id
              } label: {
                HStack {
                  Image(systemName: activeLayerID == layer.id ? "checkmark.circle.fill" : "circle")
                  Text(layer.name)
                    .foregroundStyle(NativeTheme.ink)
                  Spacer()
                  if layer.hidden {
                    Image(systemName: "eye.slash")
                  }
                  if layer.locked {
                    Image(systemName: "lock")
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .disabled(layer.hidden || layer.locked)
              .accessibilityAddTraits(activeLayerID == layer.id ? .isSelected : [])

              Button("Rename") {
                layerName = layer.name
                namingLayerID = layer.id
              }
              .accessibilityLabel(layerActionAccessibilityLabel("Rename", layerName: layer.name))
              .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)

            FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 4) {
              Button(layer.hidden ? "Show" : "Hide") {
                mutate {
                  try document.setLayer(
                    index: index,
                    name: layer.name,
                    hidden: !layer.hidden,
                    locked: layer.locked)
                }
              }
              .accessibilityLabel(
                layerActionAccessibilityLabel(layer.hidden ? "Show" : "Hide", layerName: layer.name))
              .frame(minWidth: 44, minHeight: 44)
              Button(layer.locked ? "Unlock" : "Lock") {
                mutate {
                  try document.setLayer(
                    index: index,
                    name: layer.name,
                    hidden: layer.hidden,
                    locked: !layer.locked)
                }
              }
              .accessibilityLabel(
                layerActionAccessibilityLabel(layer.locked ? "Unlock" : "Lock", layerName: layer.name))
              .frame(minWidth: 44, minHeight: 44)

              Button("Up") {
                mutate { try document.moveLayer(from: index, to: index + 1) }
              }
              .disabled(index + 1 >= layers.count)
              .accessibilityLabel(layerActionAccessibilityLabel("Up", layerName: layer.name))
              .frame(minWidth: 44, minHeight: 44)

              Button("Down") {
                mutate { try document.moveLayer(from: index, to: index - 1) }
              }
              .disabled(index == 0)
              .accessibilityLabel(layerActionAccessibilityLabel("Down", layerName: layer.name))
              .frame(minWidth: 44, minHeight: 44)

              Button("Merge down") {
                removeLayer(index: index, mergeDown: true)
              }
              .disabled(index == 0 || layers[index - 1].locked)
              .accessibilityLabel(layerActionAccessibilityLabel("Merge down", layerName: layer.name))
              .frame(minWidth: 44, minHeight: 44)

              Button("Delete", role: .destructive) {
                deleteLayerID = layer.id
              }
              .disabled(layers.count <= 1)
              .accessibilityLabel(layerActionAccessibilityLabel("Delete", layerName: layer.name))
              .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .nativeSheetSurface()
      .navigationTitle("Layers")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Add") {
            addingLayer = true
            namingLayerID = nil
            layerName = ""
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDone)
        }
      }
      .task {
        reload()
        activeLayerID = editableActiveLayerID(layers: layers, current: activeLayerID)
      }
      .alert(
        addingLayer ? "New layer" : "Rename layer",
        isPresented: Binding(
          get: { addingLayer || namingLayerID != nil },
          set: { shown in
            if !shown {
              addingLayer = false
              namingLayerID = nil
            }
          })
      ) {
        TextField("Layer name", text: $layerName)
          .nativeFieldSurface()
        Button("Cancel", role: .cancel) {
          addingLayer = false
          namingLayerID = nil
        }
        Button("Save") {
          saveLayerName()
        }
      }
      .confirmationDialog(
        deleteTitle,
        isPresented: Binding(
          get: { deleteLayerID != nil },
          set: { shown in if !shown { deleteLayerID = nil } }),
        titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) {
          if let id = deleteLayerID,
            let index = layers.firstIndex(where: { $0.id == id })
          {
            removeLayer(index: index, mergeDown: false)
          }
          deleteLayerID = nil
        }
        Button("Cancel", role: .cancel) {
          deleteLayerID = nil
        }
      } message: {
        Text("This removes its content from every page. Undo restores the layer.")
      }
    }
  }

  private var deleteTitle: String {
    guard let id = deleteLayerID,
      let layer = layers.first(where: { $0.id == id })
    else { return "Delete layer?" }
    return "Delete \(layer.name)?"
  }

  private func saveLayerName() {
    let name = layerName.trimmingCharacters(in: .whitespacesAndNewlines)
    if addingLayer {
      do {
        try document.addLayer(name: name)
        try reloadThrowing()
        activeLayerID = layers.last?.id
        onEdit()
      } catch {
        onError(error)
      }
      addingLayer = false
      return
    }

    guard let id = namingLayerID,
      let index = layers.firstIndex(where: { $0.id == id })
    else { return }
    let layer = layers[index]
    mutate {
      try document.setLayer(
        index: index,
        name: name,
        hidden: layer.hidden,
        locked: layer.locked)
    }
    namingLayerID = nil
  }

  private func removeLayer(index: Int, mergeDown: Bool) {
    let removedID = layers[index].id
    let preferredID: String?
    if index > 0 {
      preferredID = layers[index - 1].id
    } else if layers.count > 1 {
      preferredID = layers[1].id
    } else {
      preferredID = nil
    }
    do {
      try document.removeLayer(index: index, mergeDown: mergeDown)
      try reloadThrowing()
      activeLayerID = editableActiveLayerID(
        layers: layers,
        current: activeLayerID,
        preferred: activeLayerID == removedID ? preferredID : nil)
      onEdit()
    } catch {
      onError(error)
    }
  }

  private func mutate(_ action: () throws -> Void) {
    do {
      try action()
      try reloadThrowing()
      activeLayerID = editableActiveLayerID(layers: layers, current: activeLayerID)
      onEdit()
    } catch {
      onError(error)
    }
  }

  private func reload() {
    do {
      try reloadThrowing()
    } catch {
      onError(error)
    }
  }

  private func reloadThrowing() throws {
    layers = try document.layers()
  }
}
