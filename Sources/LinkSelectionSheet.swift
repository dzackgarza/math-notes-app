import Foundation
import SwiftUI

enum LinkSelectionChoice {
  case sameNotebook
  case anotherNotebook
  case href(String)
}

struct LinkSelectionSheet: View {
  let onChoose: (LinkSelectionChoice) -> Void
  let onCancel: () -> Void

  @State private var showingDestination = false
  @State private var destination = ""
  @FocusState private var destinationFocused: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section("Destination") {
          Button("Page or bookmark", systemImage: "bookmark") {
            onChoose(.sameNotebook)
          }
          Button("Another notebook", systemImage: "books.vertical") {
            onChoose(.anotherNotebook)
          }
          Button("URL or relative notebook path", systemImage: "link") {
            destination = ""
            showingDestination = true
          }
        }
      }
      .scrollContentBackground(.hidden)
      .nativeSheetSurface()
      .navigationTitle("Link selected content")
      .navigationBarTitleDisplayMode(.inline)
      .alert("Link destination", isPresented: $showingDestination) {
        TextField("https://… or ../../Note/pages/0001.svg", text: $destination)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($destinationFocused)
          .task { destinationFocused = true }
        Button("Cancel", role: .cancel, action: onCancel)
        Button("Link") {
          onChoose(.href(destination.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}
