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
  let notebookOpen: Bool
  let listing: LibraryListing
  let folderDetails: LibraryFolderDetails?
  @Binding var query: String
  let scope: LibraryScope
  let tags: [LibraryTag]
  let tagCounts: [String: Int]
  let selectedTag: String?
  let sort: LibrarySort
  let sortDirection: LibrarySortDirection
  let grid: Bool
  let openFolder: (FolderReference) -> Void
  let openNotebook: (NotebookReference) -> Void
  let goUp: () -> Void
  let showSearch: () -> Void
  let selectScope: (LibraryScope) -> Void
  let filterScope: (LibraryScope) -> Void
  let setSort: (LibrarySort) -> Void
  let setSortDirection: (LibrarySortDirection) -> Void
  let selectTag: (String) -> Void
  let filterTag: (String) -> Void
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
  let refreshSearch: () -> Void
  let showSettings: () -> Void

  @State private var searchPresented = false

  var body: some View {
    HStack(spacing: 0) {
      librarySidebar
      Divider()
        .overlay(NativeTheme.separator)
      Group {
      if !notebookOpen && !query.isEmpty && listing.folders.isEmpty && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No Results", systemImage: "magnifyingglass")
        } description: {
          Text("Nothing matches \"\(query)\".")
        }
      } else if !notebookOpen && scope == .recent && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No recent notes.", systemImage: "clock")
        }
      } else if !notebookOpen && scope == .favorites && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("No favorite notes.", systemImage: "star")
        }
      } else if !notebookOpen && scope == .trash && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("The trash is empty.", systemImage: "trash")
        }
      } else if !notebookOpen && scope == .tag && listing.folders.isEmpty && listing.notebooks.isEmpty {
        ContentUnavailableView {
          Label("Nothing has the tag \(selectedTag ?? "").", systemImage: "tag")
        }
      } else if listing.folders.isEmpty && listing.notebooks.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          if let details = visibleFolderDetails {
            folderMetadataHeader(details)
              .padding(20)
          }
          ContentUnavailableView {
            if !notebookOpen {
              Label("No Notebooks", systemImage: "books.vertical")
            } else {
              Label("No Notes", systemImage: "pencil")
            }
          } description: {
            Text(!notebookOpen ? "Your notebooks appear here." : "This notebook has no notes yet.")
          } actions: {
            if !notebookOpen {
              Button("Create notebook", action: createNotebook)
                .buttonStyle(.borderedProminent)
            } else {
              Button("Create note", action: createNote)
                .buttonStyle(.borderedProminent)
            }
          }
        }
      } else if grid {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if let details = visibleFolderDetails {
              folderMetadataHeader(details)
                .padding(.bottom, 16)
            }
            if !listing.folders.isEmpty {
              librarySectionHeading(count: listing.folders.count, noun: "notebook")
              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)],
                spacing: 24
              ) {
                ForEach(listing.folders) { item in
                  folderCard(item)
                }
              }
              .padding(.bottom, 24)
            }
            if !listing.notebooks.isEmpty {
              librarySectionHeading(count: listing.notebooks.count, noun: "note")
              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)],
                spacing: 24
              ) {
                ForEach(listing.notebooks) { item in
                  notebookCard(item)
                }
              }
              .padding(.bottom, 24)
            }
          }
          .padding(20)
        }
      } else {
        List {
          if let details = visibleFolderDetails {
            folderMetadataHeader(details)
          }
          if !listing.folders.isEmpty {
            Section(libraryCountLabel(listing.folders.count, noun: "notebook")) {
              ForEach(listing.folders) { item in
                folderRow(item)
              }
            }
          }
          if !listing.notebooks.isEmpty {
            Section(libraryCountLabel(listing.notebooks.count, noun: "note")) {
              ForEach(listing.notebooks) { item in
                notebookRow(item)
              }
            }
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
      }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .top, spacing: 0) {
        if !notebookOpen {
          Text(libraryHeading)
            .font(NativeTheme.volumeTitle)
            .foregroundStyle(NativeTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(NativeTheme.board)
        }
      }
    }
    .background(NativeTheme.board)
    .foregroundStyle(NativeTheme.ink)
    .tint(NativeTheme.ink)
    .font(NativeTheme.body)
    .toolbarBackground(NativeTheme.board, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .navigationTitle(!notebookOpen ? "" : folder.name)
    .navigationBarTitleDisplayMode(.inline)
    .modifier(
      LibrarySearchModifier(
        enabled: !notebookOpen,
        query: $query,
        searchPresented: $searchPresented,
        refreshSearch: refreshSearch))
    .onChange(of: notebookOpen) { _, open in
      if open { searchPresented = false }
    }
    .toolbar {
      if notebookOpen {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: goUp) {
            Label("Library", systemImage: "chevron.left")
          }
          .accessibilityLabel("Back to library")
        }
      }

      ToolbarItemGroup(placement: .topBarTrailing) {
        if !notebookOpen {
          filterMenu
        }

        sortMenu

        if !notebookOpen {
          Button(action: createNotebook) {
            Label("New notebook", systemImage: "folder.badge.plus")
          }
        } else {
          Button(action: importPDF) {
            Label("Import PDF", systemImage: "doc.badge.plus")
          }

          Button(action: createNote) {
            Label("New note", systemImage: "square.and.pencil")
          }

          Menu {
            folderActions(folder)
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityLabel("\(folder.name) notebook actions")
        }

      }
    }
  }

  private func libraryCountLabel(_ count: Int, noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
  }

  private func librarySectionHeading(count: Int, noun: String) -> some View {
    Text(libraryCountLabel(count, noun: noun))
      .font(NativeTheme.callout)
      .foregroundStyle(NativeTheme.graphite)
      .padding(.top, 8)
      .padding(.bottom, 12)
  }

  private var libraryHeading: String {
    if !query.isEmpty { return "Search" }
    switch scope {
    case .recent: return "Recent"
    case .favorites: return "Favorites"
    case .trash: return "Trash"
    case .tag: return selectedTag ?? "Tags"
    case .folder: return "Library"
    }
  }

  private var filterLabel: String {
    switch scope {
    case .recent: return "Recent"
    case .favorites: return "Favorites"
    case .trash: return "Trash"
    case .tag: return selectedTag ?? "Tags"
    case .folder: return "All"
    }
  }

  private var filterMenu: some View {
    Menu {
      Button {
        filterScope(.folder)
      } label: {
        if scope == .folder {
          Label("All", systemImage: "checkmark")
        } else {
          Text("All")
        }
      }
      .accessibilityAddTraits(scope == .folder ? .isSelected : [])

      Button {
        filterScope(.recent)
      } label: {
        if scope == .recent {
          Label("Recent", systemImage: "checkmark")
        } else {
          Text("Recent")
        }
      }
      .accessibilityAddTraits(scope == .recent ? .isSelected : [])

      Button {
        filterScope(.favorites)
      } label: {
        if scope == .favorites {
          Label("Favorites", systemImage: "checkmark")
        } else {
          Text("Favorites")
        }
      }
      .accessibilityAddTraits(scope == .favorites ? .isSelected : [])

      Button {
        filterScope(.trash)
      } label: {
        if scope == .trash {
          Label("Trash", systemImage: "checkmark")
        } else {
          Text("Trash")
        }
      }
      .accessibilityAddTraits(scope == .trash ? .isSelected : [])

      if !tags.isEmpty {
        Divider()
        Section("Tags") {
          ForEach(tags) { tag in
            Button {
              filterTag(tag.name)
            } label: {
              HStack {
                Image(systemName: "circle.fill")
                  .font(.system(size: 12))
                  .foregroundStyle(NativeTheme.color(tag.color))
                Text(tag.name)
                if scope == .tag && selectedTag == tag.name {
                  Image(systemName: "checkmark")
                }
              }
            }
            .accessibilityAddTraits(scope == .tag && selectedTag == tag.name ? .isSelected : [])
          }
        }
      }
    } label: {
      Label(filterLabel, systemImage: "line.3.horizontal.decrease")
    }
  }

  private var sortMenu: some View {
    Menu {
      Button {
        setSort(.name)
      } label: {
        if sort == .name {
          Label("Name", systemImage: "checkmark")
        } else {
          Text("Name")
        }
      }
      .accessibilityAddTraits(sort == .name ? .isSelected : [])

      Button {
        setSort(.modified)
      } label: {
        if sort == .modified {
          Label("Date modified", systemImage: "checkmark")
        } else {
          Text("Date modified")
        }
      }
      .accessibilityAddTraits(sort == .modified ? .isSelected : [])

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
        .accessibilityAddTraits(sortDirection == .ascending ? .isSelected : [])

        Button {
          setSortDirection(.descending)
        } label: {
          if sortDirection == .descending {
            Label("Z to A", systemImage: "checkmark")
          } else {
            Text("Z to A")
          }
        }
        .accessibilityAddTraits(sortDirection == .descending ? .isSelected : [])
      } else {
        Button {
          setSortDirection(.descending)
        } label: {
          if sortDirection == .descending {
            Label("Newest first", systemImage: "checkmark")
          } else {
            Text("Newest first")
          }
        }
        .accessibilityAddTraits(sortDirection == .descending ? .isSelected : [])

        Button {
          setSortDirection(.ascending)
        } label: {
          if sortDirection == .ascending {
            Label("Oldest first", systemImage: "checkmark")
          } else {
            Text("Oldest first")
          }
        }
        .accessibilityAddTraits(sortDirection == .ascending ? .isSelected : [])
      }

      Divider()

      Button {
        if !grid { toggleLayout() }
      } label: {
        if grid {
          Label("Grid", systemImage: "checkmark")
        } else {
          Text("Grid")
        }
      }
      .accessibilityAddTraits(grid ? .isSelected : [])

      Button {
        if grid { toggleLayout() }
      } label: {
        if !grid {
          Label("List", systemImage: "checkmark")
        } else {
          Text("List")
        }
      }
      .accessibilityAddTraits(!grid ? .isSelected : [])
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var librarySidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Math Notes")
        .font(NativeTheme.title)
        .foregroundStyle(NativeTheme.ink)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 16)

      sidebarRow(
        "Library",
        systemImage: "books.vertical",
        selected: scope == .folder && query.isEmpty
      ) {
        searchPresented = false
        selectScope(.folder)
      }
      sidebarRow(
        "Search",
        systemImage: "magnifyingglass",
        selected: scope == .folder && !query.isEmpty
      ) {
        showSearch()
        searchPresented = true
      }
      sidebarRow("Recent", systemImage: "clock", selected: scope == .recent) {
        searchPresented = false
        selectScope(.recent)
      }
      sidebarRow("Favorites", systemImage: "star", selected: scope == .favorites) {
        searchPresented = false
        selectScope(.favorites)
      }
      sidebarRow("Trash", systemImage: "trash", selected: scope == .trash) {
        searchPresented = false
        selectScope(.trash)
      }

      if !tags.isEmpty {
        Text("Tags")
          .font(NativeTheme.footnote)
          .foregroundStyle(NativeTheme.graphite)
          .padding(.horizontal, 12)
          .padding(.top, 20)
          .padding(.bottom, 4)
      } else {
        Color.clear
          .frame(height: 12)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(tags) { tag in
            sidebarTagRow(tag)
          }
          sidebarRow("New tag", systemImage: "plus", selected: false) {
            createTag()
          }
        }
      }

      sidebarRow("Settings", systemImage: "gearshape", selected: false) {
        showSettings()
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 16)
    .padding(.bottom, 12)
    .frame(width: 220)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(NativeTheme.board)
  }

  private func sidebarRow(
    _ title: String,
    systemImage: String,
    selected: Bool,
    count: Int? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .frame(width: 20)
          .foregroundStyle(selected ? NativeTheme.ribbon : NativeTheme.ink)
        Text(title)
          .font(selected ? NativeTheme.headline : NativeTheme.body)
          .foregroundStyle(NativeTheme.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        if let count {
          Text("\(count)")
            .font(NativeTheme.callout)
            .foregroundStyle(NativeTheme.graphite)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .hoverEffect(.highlight)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .background(
      selected ? NativeTheme.leaf : Color.clear,
      in: RoundedRectangle(cornerRadius: 8))
  }

  private func sidebarTagRow(_ tag: LibraryTag) -> some View {
    Button {
      searchPresented = false
      selectTag(tag.name)
    } label: {
      HStack(spacing: 10) {
        Circle()
          .fill(NativeTheme.color(tag.color))
          .frame(width: 10, height: 10)
          .frame(width: 20)
        Text(tag.name)
          .font(scope == .tag && selectedTag == tag.name ? NativeTheme.headline : NativeTheme.body)
          .foregroundStyle(NativeTheme.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        Text("\(tagCounts[tag.name] ?? 0)")
          .font(NativeTheme.callout)
          .foregroundStyle(NativeTheme.graphite)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .hoverEffect(.highlight)
    .accessibilityAddTraits(
      scope == .tag && selectedTag == tag.name ? .isSelected : [])
    .background(
      scope == .tag && selectedTag == tag.name
        ? NativeTheme.leaf : Color.clear,
      in: RoundedRectangle(cornerRadius: 8))
  }

  private var visibleFolderDetails: LibraryFolderDetails? {
    guard notebookOpen,
      let folderDetails,
      !folderDetails.description.isEmpty || !folderDetails.tags.isEmpty
    else { return nil }
    return folderDetails
  }

  @ViewBuilder
  private func folderMetadataHeader(_ details: LibraryFolderDetails) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if !details.description.isEmpty {
        Text(details.description)
          .font(NativeTheme.body)
          .foregroundStyle(NativeTheme.ink)
      }
      LibraryTagChips(tags: details.tags, knownTags: tags)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func entryActions(_ entry: LibraryEntryTarget) -> some View {
    Button("Rename", systemImage: "pencil") {
      renameEntry(entry)
    }
    Button("Move", systemImage: "folder") {
      moveEntry(entry)
    }
    Button("Move to trash", systemImage: "trash", role: .destructive) {
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
      if item.conflicts > 0 {
        Button("Compare conflicting versions", systemImage: "exclamationmark.triangle") {
          reviewConflicts(item.reference)
        }
      }
      Button(
        item.favorite ? "Remove favorite" : "Add favorite",
        systemImage: item.favorite ? "star.fill" : "star")
      {
        toggleFavorite(item)
      }
      Button("Details and tags", systemImage: "tag") {
        editNoteDetails(item.reference)
      }
      entryActions(LibraryEntryTarget(path: item.reference.path, kind: .note))
    }
  }

  @ViewBuilder
  private func folderActions(_ reference: FolderReference) -> some View {
    Button("Details and tags", systemImage: "tag") {
      editFolderDetails(reference)
    }
    if !reference.path.isEmpty {
      entryActions(LibraryEntryTarget(path: reference.path, kind: .folder))
    }
  }

  @ViewBuilder
  private func folderActions(_ item: LibraryFolderItem) -> some View {
    folderActions(item.reference)
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
        searchPresented = false
        openFolder(item.reference)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          LibraryNotebookCover(root: root, item: item, titled: true)
            .aspectRatio(0.72, contentMode: .fit)
            .frame(maxWidth: .infinity)

          VStack(alignment: .leading, spacing: 0) {
            notebookSummary(item)
            LibraryTagChips(tags: item.details.tags, knownTags: tags)
          }
          .padding(.trailing, 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .hoverEffect(.highlight)
      .accessibilityLabel("Open \(item.reference.name)")

      folderActionsButton(item)
    }
    .aspectRatio(0.62, contentMode: .fit)
    .contextMenu {
      folderActions(item)
    }
  }

  @ViewBuilder
  private func notebookSummary(_ item: LibraryFolderItem) -> some View {
    if item.noteCount == 0 {
      Text("No notes")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)
    } else if let modified = item.modified {
      Text("\(item.noteCount) note\(item.noteCount == 1 ? "" : "s") · \(libraryModifiedLabel(modified))")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)
        .lineLimit(1)
    }
  }

  private func noteMetadataLine(_ item: LibraryNotebookItem) -> String {
    var parts: [String] = []
    if !notebookOpen && scope != .trash && (!query.isEmpty || scope != .folder) {
      let parent = FolderReference(path: Array(item.reference.path.dropLast()))
      parts.append(parent.name)
    }
    parts.append(libraryModifiedLabel(item.modified))
    return parts.joined(separator: " · ")
  }

  private func notebookCard(_ item: LibraryNotebookItem) -> some View {
    ZStack(alignment: .bottomTrailing) {
      if scope == .trash {
        Menu {
          noteActions(item)
        } label: {
          notebookCardContent(item)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Open \(item.reference.name)")
      } else {
        Button {
          openNotebook(item.reference)
        } label: {
          notebookCardContent(item)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Open \(item.reference.name)")
      }

      noteActionsButton(item)
    }
    .aspectRatio(0.60, contentMode: .fit)
    .contextMenu {
      noteActions(item)
    }
  }

  private func notebookCardContent(_ item: LibraryNotebookItem) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      LibraryThumbnail(root: root, item: item)
        .aspectRatio(0.72, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(NativeTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: NativeTheme.ink.opacity(0.18), radius: 9, y: 3)

      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 6) {
          if item.conflicts > 0 {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(NativeTheme.warning)
              .accessibilityLabel("Conflicting versions")
          }
          Text(item.reference.name)
            .font(NativeTheme.headline)
            .lineLimit(1)
        }

        Text(noteMetadataLine(item))
          .font(NativeTheme.footnote)
          .foregroundStyle(NativeTheme.graphite)
          .lineLimit(1)
        LibraryTagChips(tags: item.details.tags, knownTags: tags)
      }
      .padding(.trailing, 36)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func folderRow(_ item: LibraryFolderItem) -> some View {
    HStack(spacing: 8) {
      Button {
        searchPresented = false
        openFolder(item.reference)
      } label: {
        HStack(spacing: 16) {
          LibraryNotebookCover(root: root, item: item, titled: false)
            .frame(width: 48, height: 64)

          VStack(alignment: .leading, spacing: 4) {
            Text(item.reference.name)
              .font(NativeTheme.headline)
            notebookSummary(item)
            LibraryTagChips(tags: item.details.tags, knownTags: tags)
          }
        }
      }
      .buttonStyle(.plain)
      .hoverEffect(.highlight)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel("Open \(item.reference.name)")

      folderActionsButton(item)
    }
    .contextMenu {
      folderActions(item)
    }
  }

  private func notebookRow(_ item: LibraryNotebookItem) -> some View {
    HStack(spacing: 8) {
      if scope == .trash {
        Menu {
          noteActions(item)
        } label: {
          notebookRowContent(item)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Open \(item.reference.name)")
      } else {
        Button {
          openNotebook(item.reference)
        } label: {
          notebookRowContent(item)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Open \(item.reference.name)")
      }

      noteActionsButton(item)
    }
    .contextMenu {
      noteActions(item)
    }
  }

  private func notebookRowContent(_ item: LibraryNotebookItem) -> some View {
    HStack(spacing: 16) {
      LibraryThumbnail(root: root, item: item)
        .frame(width: 48, height: 64)
        .background(NativeTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 4))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          if item.conflicts > 0 {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(NativeTheme.warning)
              .accessibilityLabel("Conflicting versions")
          }
          Text(item.reference.name)
            .font(NativeTheme.headline)
        }
        Text(noteMetadataLine(item))
          .font(NativeTheme.footnote)
          .foregroundStyle(NativeTheme.graphite)
          .lineLimit(1)
        LibraryTagChips(tags: item.details.tags, knownTags: tags)
      }
    }
  }
}

@MainActor
struct LibraryThumbnail: View {
  let root: NotesRootAccess
  let item: LibraryNotebookItem

  @State private var image: UIImage?
  @State private var missing = false
  @State private var failureMessage: String?

  var body: some View {
    ZStack {
      Rectangle()
        .fill(NativeTheme.paper)

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .accessibilityLabel("\(item.reference.name) first page")
      } else if let failureMessage {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(NativeTheme.graphite)
          .accessibilityLabel("Thumbnail failed: \(failureMessage)")
      } else if missing {
        Image(systemName: "doc")
          .foregroundStyle(NativeTheme.graphite)
          .accessibilityLabel("No thumbnail for \(item.reference.name)")
      } else {
        ProgressView()
      }
    }
    .overlay(alignment: .topTrailing) {
      if item.conflicts > 0 {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 14))
          .foregroundStyle(NativeTheme.warning)
          .padding(4)
          .background(NativeTheme.board, in: Circle())
          .padding(4)
          .accessibilityLabel("Conflicting versions")
      }
    }
    .task(id: item.modified) {
      image = nil
      missing = false
      failureMessage = nil
      do {
        guard let data = try root.thumbnail(item.reference) else {
          missing = true
          return
        }
        guard let rendered = UIImage(data: data) else {
          failureMessage = "Invalid image data"
          return
        }
        image = rendered
      } catch {
        image = nil
        failureMessage = error.localizedDescription
      }
    }
  }
}

@MainActor
struct NotebookCoverArt<Page: View>: View {
  let color: Color
  let edgeColor: Color
  let style: String
  let title: String?
  let page: Page

  init(
    color: Color,
    edgeColor: Color,
    style: String,
    title: String?,
    @ViewBuilder page: () -> Page
  ) {
    self.color = color
    self.edgeColor = edgeColor
    self.style = style
    self.title = title
    self.page = page()
  }

  var body: some View {
    let coverShape = UnevenRoundedRectangle(
      topLeadingRadius: 2,
      bottomLeadingRadius: 2,
      bottomTrailingRadius: 6,
      topTrailingRadius: 6)
    ZStack(alignment: .leading) {
      coverShape
        .fill(color)
      Rectangle()
        .fill(edgeColor)
        .frame(width: style == "spine" ? 12 : 4)
      VStack(spacing: title == nil ? 0 : 10) {
        page
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let title {
          Text(title)
            .font(NativeTheme.spineTitle)
            .foregroundStyle(NativeTheme.ink)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(NativeTheme.paper)
        }
      }
      .padding(title == nil ? 6 : 10)
    }
    .clipShape(coverShape)
    .shadow(
      color: NativeTheme.ink.opacity(0.18),
      radius: 9,
      y: 3)
  }
}

@MainActor
struct LibraryNotebookCover: View {
  let root: NotesRootAccess
  let item: LibraryFolderItem
  let titled: Bool

  @State private var thumbnail: UIImage?
  @State private var thumbnailMissing = false
  @State private var thumbnailFailureMessage: String?
  @State private var thumbnailConflicts = false

  var body: some View {
    NotebookCoverArt(
      color: coverColor,
      edgeColor: NativeTheme.coverEdge(item.details.coverColor),
      style: item.details.coverStyle,
      title: titled ? item.reference.name : nil
    ) {
      Group {
        if let thumbnail {
          Image(uiImage: thumbnail)
            .resizable()
            .scaledToFit()
            .background(NativeTheme.paper)
        } else if let thumbnailFailureMessage {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(NativeTheme.graphite)
            .accessibilityLabel("Thumbnail failed: \(thumbnailFailureMessage)")
        } else if thumbnailMissing {
          Image(systemName: "doc")
            .foregroundStyle(NativeTheme.graphite)
            .accessibilityLabel("No thumbnail")
        } else {
          Color.clear
        }
      }
      .overlay(alignment: .topTrailing) {
        if thumbnailConflicts {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 14))
            .foregroundStyle(NativeTheme.warning)
            .padding(4)
            .background(NativeTheme.board, in: Circle())
            .padding(4)
            .accessibilityLabel("Conflicting versions")
        }
      }
    }
    .task(id: thumbnailKey) {
      thumbnail = nil
      thumbnailMissing = false
      thumbnailFailureMessage = nil
      thumbnailConflicts = false
      guard let coverNote = item.coverNote else { return }
      do {
        guard let data = try root.thumbnail(coverNote) else {
          thumbnailMissing = true
          return
        }
        guard let rendered = UIImage(data: data) else {
          thumbnailFailureMessage = "Invalid image data"
          return
        }
        thumbnail = rendered
        thumbnailConflicts = try root.conflictCount(coverNote) > 0
      } catch {
        thumbnail = nil
        thumbnailFailureMessage = error.localizedDescription
      }
    }
    .accessibilityLabel("\(item.reference.name) notebook cover")
  }

  private var thumbnailKey: String {
    "\(item.coverNote?.id ?? "")@\(item.modified?.timeIntervalSince1970 ?? 0)"
  }

  private var coverColor: Color {
    NativeTheme.color(item.details.coverColor)
  }
}

struct LibraryTagChips: View {
  let tags: [String]
  let knownTags: [LibraryTag]

  var body: some View {
    if !tags.isEmpty {
      FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 0) {
        ForEach(tags, id: \.self) { tag in
          HStack(spacing: 4) {
            Circle()
              .fill(tagColor(tag))
              .frame(width: 8, height: 8)
            Text(tag)
              .font(NativeTheme.footnote)
              .foregroundStyle(NativeTheme.graphite)
          }
          .fixedSize()
        }
      }
    }
  }

  private func tagColor(_ name: String) -> Color {
    guard let tag = knownTags.first(where: { $0.name == name }) else {
      return NativeTheme.color("#8E8E93")
    }
    return NativeTheme.color(tag.color)
  }
}
