import SwiftUI
import UIKit

enum LibraryScope: String {
  case folder
  case recent
  case favorites
  case trash
  case tag
}

@MainActor
struct NativeLibraryView: View {
  let root: NotesRootAccess
  let folder: FolderReference
  let listing: LibraryListing
  @Binding var query: String
  @Binding var scope: LibraryScope
  let tags: [LibraryTag]
  let selectedTag: String?
  let sort: LibrarySort
  let sortDirection: LibrarySortDirection
  let grid: Bool
  let openFolder: (FolderReference) -> Void
  let openNotebook: (NotebookReference) -> Void
  let goUp: () -> Void
  let setSort: (LibrarySort) -> Void
  let setSortDirection: (LibrarySortDirection) -> Void
  let selectTag: (String) -> Void
  let createTag: () -> Void
  let toggleLayout: () -> Void
  let createNote: () -> Void
  let createNotebook: () -> Void
  let importPDF: () -> Void
  let renameEntry: (LibraryEntryTarget) -> Void
  let moveEntry: (LibraryEntryTarget) -> Void
  let trashEntry: (LibraryEntryTarget) -> Void
  let restoreEntry: (LibraryEntryTarget) -> Void
  let toggleFavorite: (LibraryNotebookItem) -> Void
  let editNoteDetails: (NotebookReference) -> Void
  let editFolderDetails: (FolderReference) -> Void
  let reviewConflicts: (NotebookReference) -> Void
  let refresh: () -> Void
  let showSettings: () -> Void

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
      } else if scope == .favorites && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No Favorites", systemImage: "star")
        } description: {
          Text("Add a note to Favorites from its menu.")
        }
      } else if scope == .trash && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("Trash is Empty", systemImage: "trash")
        } description: {
          Text("Notes moved to Trash appear here until restored in Files or Math Notes.")
        }
      } else if scope == .tag && listing.folders.isEmpty && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No Tagged Notes", systemImage: "tag")
        } description: {
          Text("Nothing has the tag \(selectedTag ?? "").")
        }
      } else if listing.folders.isEmpty && listing.notebooks.isEmpty {
        ContentUnavailableView {
          if folder.path.isEmpty {
            Label("No Notebooks", systemImage: "books.vertical")
          } else {
            Label("No Notes", systemImage: "pencil")
          }
        } description: {
          Text(folder.path.isEmpty ? "Your notebooks appear here." : "This notebook has no notes yet.")
        } actions: {
          if folder.path.isEmpty {
            Button("Create Notebook", action: createNotebook)
              .buttonStyle(.borderedProminent)
          } else {
            Button("Create Note", action: createNote)
              .buttonStyle(.borderedProminent)
          }
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
      !query.isEmpty
        ? "Search"
        : scope == .recent
        ? "Recent"
        : scope == .favorites
        ? "Favorites"
        : scope == .trash
        ? "Trash"
        : scope == .tag
        ? selectedTag ?? "Tags"
        : folder.name)
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
        if folder.path.isEmpty {
          Button(action: createNotebook) {
            Label("New Notebook", systemImage: "folder.badge.plus")
          }
        } else {
          Button(action: createNote) {
            Label("New Note", systemImage: "square.and.pencil")
          }
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
            setSortDirection(.descending)
            scope = .recent
          } label: {
            if scope == .recent {
              Label("Recent", systemImage: "checkmark")
            } else {
              Label("Recent", systemImage: "clock")
            }
          }

          Button {
            scope = .favorites
          } label: {
            if scope == .favorites {
              Label("Favorites", systemImage: "checkmark")
            } else {
              Label("Favorites", systemImage: "star")
            }
          }

          Button {
            scope = .trash
          } label: {
            if scope == .trash {
              Label("Trash", systemImage: "checkmark")
            } else {
              Label("Trash", systemImage: "trash")
            }
          }

          if !tags.isEmpty {
            Divider()
            ForEach(tags) { tag in
              Button {
                selectTag(tag.name)
              } label: {
                if scope == .tag && selectedTag == tag.name {
                  Label(tag.name, systemImage: "checkmark")
                } else {
                  Label(tag.name, systemImage: "tag")
                }
              }
            }
          }

          Button(action: createTag) {
            Label("New Tag…", systemImage: "tag.badge.plus")
          }

          if !folder.path.isEmpty {
            Divider()

            Button(action: importPDF) {
              Label("Import PDF", systemImage: "doc.badge.plus")
            }
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

          if sort == .name {
            Button {
              setSortDirection(.ascending)
            } label: {
              if sortDirection == .ascending {
                Label("A to Z", systemImage: "checkmark")
              } else {
                Text("A to Z")
              }
            }

            Button {
              setSortDirection(.descending)
            } label: {
              if sortDirection == .descending {
                Label("Z to A", systemImage: "checkmark")
              } else {
                Text("Z to A")
              }
            }
          } else {
            Button {
              setSortDirection(.descending)
            } label: {
              if sortDirection == .descending {
                Label("Newest First", systemImage: "checkmark")
              } else {
                Text("Newest First")
              }
            }

            Button {
              setSortDirection(.ascending)
            } label: {
              if sortDirection == .ascending {
                Label("Oldest First", systemImage: "checkmark")
              } else {
                Text("Oldest First")
              }
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

          Button(action: showSettings) {
            Label("Settings", systemImage: "gearshape")
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

  @ViewBuilder
  private func noteActions(_ item: LibraryNotebookItem) -> some View {
    if scope == .trash {
      Button("Restore", systemImage: "arrow.uturn.backward") {
        restoreEntry(LibraryEntryTarget(path: item.reference.path, kind: .note))
      }
    } else {
      Button(
        item.favorite ? "Remove Favorite" : "Add Favorite",
        systemImage: item.favorite ? "star.fill" : "star")
      {
        toggleFavorite(item)
      }
      Button("Details and Tags", systemImage: "tag") {
        editNoteDetails(item.reference)
      }
      if item.conflicts > 0 {
        Button("Compare conflicting versions", systemImage: "exclamationmark.triangle") {
          reviewConflicts(item.reference)
        }
      }
      Divider()
      entryActions(LibraryEntryTarget(path: item.reference.path, kind: .note))
    }
  }

  @ViewBuilder
  private func folderActions(_ item: LibraryFolderItem) -> some View {
    Button("Details and Tags", systemImage: "tag") {
      editFolderDetails(item.reference)
    }
    Divider()
    entryActions(LibraryEntryTarget(path: item.reference.path, kind: .folder))
  }

  private func folderActionsButton(_ item: LibraryFolderItem) -> some View {
    Menu {
      folderActions(item)
    } label: {
      Image(systemName: "ellipsis.circle")
        .frame(width: 32, height: 32)
    }
    .accessibilityLabel("\(item.reference.name) notebook actions")
  }

  private func noteActionsButton(_ item: LibraryNotebookItem) -> some View {
    Menu {
      noteActions(item)
    } label: {
      Image(systemName: "ellipsis.circle")
        .frame(width: 32, height: 32)
    }
    .accessibilityLabel("\(item.reference.name) actions")
  }

  private func folderCard(_ item: LibraryFolderItem) -> some View {
    ZStack(alignment: .bottomTrailing) {
      Button {
        openFolder(item.reference)
      } label: {
        VStack(alignment: .leading, spacing: 10) {
          LibraryNotebookCover(root: root, item: item, titled: true)
            .aspectRatio(0.72, contentMode: .fit)
            .frame(maxWidth: .infinity)

          VStack(alignment: .leading, spacing: 4) {
            notebookSummary(item)
            LibraryTagChips(tags: item.details.tags)
          }
          .padding(.trailing, 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open \(item.reference.name)")

      folderActionsButton(item)
    }
    .contextMenu {
      folderActions(item)
    }
  }

  @ViewBuilder
  private func notebookSummary(_ item: LibraryFolderItem) -> some View {
    if item.noteCount == 0 {
      Text("No notes")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else if let modified = item.modified {
      Text("\(item.noteCount) note\(item.noteCount == 1 ? "" : "s") · \(modified.formatted(.dateTime.month(.abbreviated).day().year()))")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  private func notebookCard(_ item: LibraryNotebookItem) -> some View {
    ZStack(alignment: .bottomTrailing) {
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

          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              if item.conflicts > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
                  .accessibilityLabel("Conflicting versions")
              }
              Text(item.reference.name)
                .font(.headline)
                .lineLimit(2)
            }

            if !query.isEmpty || scope != .folder {
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
            LibraryTagChips(tags: item.details.tags)
          }
          .padding(.trailing, 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open \(item.reference.name)")

      noteActionsButton(item)
    }
    .contextMenu {
      noteActions(item)
    }
  }

  private func folderRow(_ item: LibraryFolderItem) -> some View {
    HStack(spacing: 8) {
      Button {
        openFolder(item.reference)
      } label: {
        HStack(spacing: 14) {
          LibraryNotebookCover(root: root, item: item, titled: false)
            .frame(width: 44, height: 58)

          VStack(alignment: .leading, spacing: 4) {
            Text(item.reference.path.last ?? item.reference.name)
              .font(.headline)
            notebookSummary(item)
            LibraryTagChips(tags: item.details.tags)
          }
        }
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)

      folderActionsButton(item)
    }
    .contextMenu {
      folderActions(item)
    }
  }

  private func notebookRow(_ item: LibraryNotebookItem) -> some View {
    HStack(spacing: 8) {
      Button {
        openNotebook(item.reference)
      } label: {
        HStack(spacing: 14) {
          LibraryThumbnail(root: root, item: item)
            .frame(width: 48, height: 64)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 4))

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              if item.conflicts > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
                  .accessibilityLabel("Conflicting versions")
              }
              Text(item.reference.name)
                .font(.headline)
            }
            if !query.isEmpty || scope != .folder {
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
            LibraryTagChips(tags: item.details.tags)
          }
        }
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)

      noteActionsButton(item)
    }
    .contextMenu {
      noteActions(item)
    }
  }
}

@MainActor
struct LibraryThumbnail: View {
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

@MainActor
struct LibraryNotebookCover: View {
  let root: NotesRootAccess
  let item: LibraryFolderItem
  let titled: Bool

  @State private var thumbnail: UIImage?

  var body: some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: 6)
        .fill(coverColor)
      Rectangle()
        .fill(coverColor.opacity(0.55))
        .frame(width: item.details.coverStyle == "spine" ? 12 : 4)
      VStack(spacing: titled ? 10 : 0) {
        Group {
          if let thumbnail {
            Image(uiImage: thumbnail)
              .resizable()
              .scaledToFit()
              .background(.white)
          } else {
            Color.clear
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if titled {
          Text(item.reference.path.last ?? item.reference.name)
            .font(.headline)
            .foregroundStyle(.black.opacity(0.8))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white)
        }
      }
      .padding(titled ? 10 : 6)
    }
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .shadow(radius: titled ? 2 : 1, y: 1)
    .task(id: item.modified) {
      do {
        let listing = try root.library(in: item.reference, sort: .modified, direction: .descending)
        if let first = listing.notebooks.first, let data = try root.thumbnail(first.reference) {
          thumbnail = UIImage(data: data)
        } else {
          thumbnail = nil
        }
      } catch {
        thumbnail = nil
      }
    }
    .accessibilityLabel("\(item.reference.name) notebook cover")
  }

  private var coverColor: Color {
    let hex = item.details.coverColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard hex.count == 6, let rgb = UInt64(hex, radix: 16) else { return .secondary }
    return Color(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255)
  }
}

struct LibraryTagChips: View {
  let tags: [String]

  var body: some View {
    if !tags.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: 4) {
          ForEach(tags, id: \.self) { tag in
            Text(tag)
              .font(.caption2)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.quaternary, in: Capsule())
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }
}
