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
      VStack(spacing: 0) {
        HStack(spacing: 4) {
          TextField("Search", text: $query)
            .nativeFieldSurface()
          if !query.isEmpty {
            Button { query = "" } label: {
              Image(systemName: "xmark.circle.fill")
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear search")
          }
        }
        .padding(12)

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
                      .foregroundStyle(NativeTheme.ink)
                    let folder = FolderReference(path: Array(item.reference.path.dropLast()))
                    Text(folder.name)
                      .font(NativeTheme.footnote)
                      .foregroundStyle(NativeTheme.graphite)
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
      }
      .scrollContentBackground(.hidden)
      .nativeSheetSurface()
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    }
  }
}
