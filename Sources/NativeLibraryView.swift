import SwiftUI
import UIKit

enum LibraryScope: String {
  case folder
  case recent
}

@MainActor
struct NativeLibraryView: View {
  let root: NotesRootAccess
  let folder: FolderReference
  let listing: LibraryListing
  @Binding var query: String
  @Binding var scope: LibraryScope
  let sort: LibrarySort
  let grid: Bool
  let openFolder: (FolderReference) -> Void
  let openNotebook: (NotebookReference) -> Void
  let goUp: () -> Void
  let setSort: (LibrarySort) -> Void
  let toggleLayout: () -> Void
  let createNote: () -> Void
  let importPDF: () -> Void
  let createFolder: () -> Void
  let renameEntry: (LibraryEntryTarget) -> Void
  let moveEntry: (LibraryEntryTarget) -> Void
  let trashEntry: (LibraryEntryTarget) -> Void
  let refresh: () -> Void
  let chooseRoot: () -> Void

  var body: some View {
    Group {
      if !query.isEmpty && listing.folders.isEmpty && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No Results", systemImage: "magnifyingglass")
        } description: {
          Text("Nothing matches “\(query)”.")
        }
      } else if scope == .recent && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No Recent Notes", systemImage: "clock")
        } description: {
          Text("Notes appear here after they are created or edited.")
        }
      } else if listing.folders.isEmpty && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No Notes Here", systemImage: "folder")
        } description: {
          Text("This folder has no note folders yet.")
        } actions: {
          Button("New Note", action: createNote)
            .buttonStyle(.borderedProminent)
          Button("Rescan", action: refresh)
        }
      } else if grid {
        ScrollView {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 20)],
            spacing: 24
          ) {
            ForEach(listing.folders) { item in
              folderCard(item)
            }
            ForEach(listing.notebooks) { item in
              notebookCard(item)
            }
          }
          .padding(20)
        }
      } else {
        List {
          if !listing.folders.isEmpty {
            Section("Folders") {
              ForEach(listing.folders) { item in
                folderRow(item)
              }
            }
          }
          if !listing.notebooks.isEmpty {
            Section("Notes") {
              ForEach(listing.notebooks) { item in
                notebookRow(item)
              }
            }
          }
        }
        .listStyle(.insetGrouped)
      }
    }
    .navigationTitle(
      !query.isEmpty ? "Search" : scope == .recent ? "Recent" : folder.name)
    .navigationBarTitleDisplayMode(.large)
    .searchable(
      text: $query,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search notebooks and notes")
    .onChange(of: query) {
      refresh()
    }
    .onChange(of: scope) {
      refresh()
    }
    .toolbar {
      if scope == .folder && !folder.path.isEmpty {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: goUp) {
            Label("Up", systemImage: "chevron.left")
          }
        }
      }

      ToolbarItemGroup(placement: .topBarTrailing) {
        Button(action: createNote) {
          Label("New Note", systemImage: "square.and.pencil")
        }

        Menu {
          Button {
            scope = .folder
          } label: {
            if scope == .folder {
              Label("Library", systemImage: "checkmark")
            } else {
              Label("Library", systemImage: "books.vertical")
            }
          }

          Button {
            setSort(.modified)
            scope = .recent
          } label: {
            if scope == .recent {
              Label("Recent", systemImage: "checkmark")
            } else {
              Label("Recent", systemImage: "clock")
            }
          }

          Divider()

          Button(action: importPDF) {
            Label("Import PDF", systemImage: "doc.badge.plus")
          }

          Divider()

          Button(action: createFolder) {
            Label("New Folder", systemImage: "folder.badge.plus")
          }

          Divider()

          Button {
            setSort(.name)
          } label: {
            if sort == .name {
              Label("Name", systemImage: "checkmark")
            } else {
              Text("Name")
            }
          }

          Button {
            setSort(.modified)
          } label: {
            if sort == .modified {
              Label("Date Modified", systemImage: "checkmark")
            } else {
              Text("Date Modified")
            }
          }

          Divider()

          Button(action: toggleLayout) {
            Label(
              grid ? "List" : "Grid",
              systemImage: grid ? "list.bullet" : "square.grid.2x2")
          }

          Divider()

          Button(action: refresh) {
            Label("Rescan", systemImage: "arrow.clockwise")
          }

          Button(action: chooseRoot) {
            Label("Change Notes Folder", systemImage: "folder")
          }
        } label: {
          Label("Library Options", systemImage: "ellipsis.circle")
        }
      }
    }
  }

  @ViewBuilder
  private func entryActions(_ entry: LibraryEntryTarget) -> some View {
    Button("Rename", systemImage: "pencil") {
      renameEntry(entry)
    }
    Button("Move", systemImage: "folder") {
      moveEntry(entry)
    }
    Divider()
    Button("Move to Trash", systemImage: "trash", role: .destructive) {
      trashEntry(entry)
    }
  }

  private func folderCard(_ item: LibraryFolderItem) -> some View {
    Button {
      openFolder(item.reference)
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        RoundedRectangle(cornerRadius: 16)
          .fill(.quaternary)
          .aspectRatio(4 / 3, contentMode: .fit)
          .overlay {
            Image(systemName: "folder.fill")
              .font(.system(size: 48))
              .foregroundStyle(.secondary)
          }

        Text(item.reference.path.last ?? item.reference.name)
          .font(.headline)
          .lineLimit(2)

        if let modified = item.modified {
          Text(modified, format: .dateTime.month(.abbreviated).day().year())
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Empty folder")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open \(item.reference.name)")
    .contextMenu {
      entryActions(LibraryEntryTarget(path: item.reference.path, kind: .folder))
    }
  }

  private func notebookCard(_ item: LibraryNotebookItem) -> some View {
    Button {
      openNotebook(item.reference)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        LibraryThumbnail(root: root, item: item)
          .aspectRatio(0.72, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .background(.background)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .shadow(radius: 2, y: 1)

        Text(item.reference.name)
          .font(.headline)
          .lineLimit(2)

        if !query.isEmpty || scope == .recent {
          let parent = item.reference.path.dropLast().joined(separator: " / ")
          if !parent.isEmpty {
            Text(parent)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Text(item.modified, format: .dateTime.month(.abbreviated).day().year())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open \(item.reference.name)")
    .contextMenu {
      entryActions(LibraryEntryTarget(path: item.reference.path, kind: .note))
    }
  }

  private func folderRow(_ item: LibraryFolderItem) -> some View {
    Button {
      openFolder(item.reference)
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "folder.fill")
          .font(.title2)
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 58)

        VStack(alignment: .leading, spacing: 4) {
          Text(item.reference.path.last ?? item.reference.name)
            .font(.headline)
          if let modified = item.modified {
            Text(modified, format: .dateTime.month(.abbreviated).day().year())
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text("Empty folder")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .buttonStyle(.plain)
    .contextMenu {
      entryActions(LibraryEntryTarget(path: item.reference.path, kind: .folder))
    }
  }

  private func notebookRow(_ item: LibraryNotebookItem) -> some View {
    Button {
      openNotebook(item.reference)
    } label: {
      HStack(spacing: 14) {
        LibraryThumbnail(root: root, item: item)
          .frame(width: 48, height: 64)
          .background(.background)
          .clipShape(RoundedRectangle(cornerRadius: 4))

        VStack(alignment: .leading, spacing: 4) {
          Text(item.reference.name)
            .font(.headline)
          if !query.isEmpty || scope == .recent {
            let parent = item.reference.path.dropLast().joined(separator: " / ")
            if !parent.isEmpty {
              Text(parent)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Text(item.modified, format: .dateTime.month(.abbreviated).day().year())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .buttonStyle(.plain)
    .contextMenu {
      entryActions(LibraryEntryTarget(path: item.reference.path, kind: .note))
    }
  }
}

@MainActor
private struct LibraryThumbnail: View {
  let root: NotesRootAccess
  let item: LibraryNotebookItem

  @State private var image: UIImage?
  @State private var failed = false

  var body: some View {
    ZStack {
      Rectangle()
        .fill(.background)

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .accessibilityLabel("\(item.reference.name) first page")
      } else if failed {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
          .accessibilityLabel("Thumbnail failed")
      } else {
        ProgressView()
      }
    }
    .task(id: item.modified) {
      image = nil
      failed = false
      do {
        if let data = try root.thumbnail(item.reference),
          let rendered = UIImage(data: data)
        {
          image = rendered
        } else {
          image = nil
        }
      } catch {
        image = nil
        failed = true
      }
    }
  }
}
