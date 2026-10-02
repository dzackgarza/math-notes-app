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

  @State private var destination = ""

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
        }

        Section("URL or relative notebook path") {
          TextField("URL or relative page path", text: $destination)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

          Button("Link", systemImage: "link") {
            onChoose(.href(destination.trimmingCharacters(in: .whitespacesAndNewlines)))
          }
          .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .navigationTitle("Link selected content")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}
