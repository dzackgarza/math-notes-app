import SwiftUI

@MainActor
struct OpenNotePickerSheet: View {
  let root: NotesRootAccess
  let title: String
  let notes: [LibraryNotebookItem]
  let opened: Set<NotebookReference>
  let onOpen: (NotebookReference) -> Void
  let onCancel: () -> Void

  @State private var query = ""

  private var filteredNotes: [LibraryNotebookItem] {
    guard !query.isEmpty else { return notes }
    let needle = query.lowercased()
    return notes.filter { item in
      item.reference.name.lowercased().contains(needle)
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if filteredNotes.isEmpty {
          ContentUnavailableView {
            Label(query.isEmpty ? "No Notes" : "No Results", systemImage: "magnifyingglass")
          } description: {
            Text(query.isEmpty ? "There are no notes in this notes folder." : "No note matches the search.")
          }
        } else {
          List(filteredNotes) { item in
            Button {
              onOpen(item.reference)
            } label: {
              HStack(spacing: 12) {
                LibraryThumbnail(root: root, item: item)
                  .frame(width: 48, height: 62)
                  .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 3) {
                  Text(item.conflicts > 0 ? "⚠ \(item.reference.name)" : item.reference.name)
                    .foregroundStyle(.primary)
                  let folder = FolderReference(path: Array(item.reference.path.dropLast()))
                  Text(folder.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if opened.contains(item.reference) {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Already open")
                }
              }
            }
            .buttonStyle(.plain)
          }
          .listStyle(.insetGrouped)
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "Search")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}
