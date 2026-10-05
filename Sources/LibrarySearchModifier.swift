import Foundation
import SwiftUI

func librarySearchEnabled(folderPath: [String]) -> Bool {
  folderPath.isEmpty
}

struct LibrarySearchModifier: ViewModifier {
  let enabled: Bool
  @Binding var query: String
  @Binding var searchPresented: Bool
  let refreshSearch: () -> Void

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      content
        .searchable(
          text: Binding(
            get: { query },
            set: { query = $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
          isPresented: $searchPresented,
          placement: .navigationBarDrawer(displayMode: .always),
          prompt: "Search notebooks and notes")
        .onChange(of: query) {
          refreshSearch()
        }
    } else {
      content
    }
  }
}
