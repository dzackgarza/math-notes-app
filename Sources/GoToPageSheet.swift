import Foundation
import SwiftUI

struct GoToPageRequest: Identifiable {
  let id = UUID()
  let pageCount: Int
  let currentPage: Int
}

struct GoToPageSheet: View {
  let request: GoToPageRequest
  let onGo: (Int) -> Void
  let onCancel: () -> Void

  @State private var pageNumber: String
  @FocusState private var pageFocused: Bool

  init(
    request: GoToPageRequest,
    onGo: @escaping (Int) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.request = request
    self.onGo = onGo
    self.onCancel = onCancel
    _pageNumber = State(initialValue: String(request.currentPage + 1))
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("1 to \(request.pageCount)", text: $pageNumber)
          .keyboardType(.numberPad)
          .nativeFieldSurface()
          .focused($pageFocused)
          .task { pageFocused = true }
      }
      .scrollContentBackground(.hidden)
      .nativeSheetSurface()
      .navigationTitle("Go to page")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Go") {
            guard let page = parsedPage else { return }
            onGo(page)
          }
        }
      }
    }
  }

  private var parsedPage: Int? {
    guard let number = Int(pageNumber),
      number >= 1,
      number <= request.pageCount
    else { return nil }
    return number - 1
  }
}
