import Foundation
import SwiftUI
import UIKit

struct BookmarkDestination: Identifiable {
  let mark: EngineNavigationMark
  let preview: Data?

  var id: String { mark.key }
}

struct BookmarksRequest: Identifiable {
  let id = UUID()
  let destinations: [BookmarkDestination]
}

struct BookmarksSheet: View {
  let request: BookmarksRequest
  let onSelect: (EngineNavigationMark) -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationStack {
      List(request.destinations) { destination in
        Button {
          onSelect(destination.mark)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: destination.mark.id.isEmpty ? "doc" : "bookmark")
              .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
              Text(
                destination.mark.id.isEmpty
                  ? "Page \(destination.mark.page + 1)"
                  : "Bookmark on page \(destination.mark.page + 1)")
                .foregroundStyle(.primary)

              if let preview = destination.preview,
                let image = UIImage(data: preview)
              {
                Image(uiImage: image)
                  .resizable()
                  .scaledToFit()
                  .frame(height: 48)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }
        .buttonStyle(.plain)
      }
      .navigationTitle("Pages and bookmarks")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}
