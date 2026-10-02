import Foundation
import InkEngine

struct FolderReference: Hashable, Identifiable {
  let path: [String]

  var id: String { path.joined(separator: "/") }
  var name: String { path.isEmpty ? "My Notes" : path.joined(separator: " / ") }
}

enum LibrarySort: String, CaseIterable, Identifiable {
  case modified
  case name

  var id: Self { self }
}

enum LibrarySortDirection: String, CaseIterable, Identifiable {
  case ascending
  case descending

  var id: Self { self }
}

struct LibraryFolderItem: Identifiable {
  let reference: FolderReference
  let modified: Date?

  var id: String { reference.id }
}

struct LibraryNotebookItem: Identifiable {
  let reference: NotebookReference
  let modified: Date
  let favorite: Bool

  var id: String { reference.id }
}

struct LibraryListing {
  let folders: [LibraryFolderItem]
  let notebooks: [LibraryNotebookItem]
}

struct NotebookReference: Hashable, Identifiable {
  let path: [String]

  var id: String { path.joined(separator: "/") }
  var name: String { path.last ?? "Untitled" }
}

struct LibraryTag: Hashable, Identifiable {
  let name: String
  let color: String

  var id: String { name }
}

struct LibraryNoteDetails: Equatable {
  var favorite: Bool
  var tags: [String]
  var description: String
}

struct LibraryFolderDetails: Equatable {
  var description: String
  var paper: String
  var coverColor: String
  var coverStyle: String
  var tags: [String]
}

enum LibraryMetadataFile {
  static let name = ".library.json"
  static let tagColors = [
    "#2F6FEB", "#3FA35B", "#8B5CF6", "#F08A24",
    "#2BB3C0", "#D6455D", "#1F3A93", "#C084FC",
  ]

  static func read(at root: URL) throws -> Data? {
    let file = root.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    return try Data(contentsOf: file)
  }

  static func favoritePaths(in data: Data?) throws -> Set<String> {
    let root = try object(from: data)
    let notes = root["notes"] as? [String: Any] ?? [:]
    return Set(notes.compactMap { key, value in
      guard let note = value as? [String: Any], note["favorite"] as? Bool == true else {
        return nil
      }
      return key
    })
  }

  static func tags(in data: Data?) throws -> [LibraryTag] {
    let root = try object(from: data)
    let values = root["tags"] as? [[String: Any]] ?? []
    return values.compactMap { value in
      guard let name = value["name"] as? String,
        let color = value["color"] as? String
      else { return nil }
      return LibraryTag(name: name, color: color)
    }
  }

  static func noteDetails(in data: Data?, path: [String]) throws -> LibraryNoteDetails {
    let root = try object(from: data)
    let notes = root["notes"] as? [String: Any] ?? [:]
    let note = notes[path.joined(separator: "/")] as? [String: Any] ?? [:]
    return LibraryNoteDetails(
      favorite: note["favorite"] as? Bool ?? false,
      tags: note["tags"] as? [String] ?? [],
      description: note["description"] as? String ?? "")
  }

  static func folderDetails(in data: Data?, path: [String]) throws -> LibraryFolderDetails {
    let root = try object(from: data)
    let folders = root["folders"] as? [String: Any] ?? [:]
    let folder = folders[path.joined(separator: "/")] as? [String: Any] ?? [:]
    return LibraryFolderDetails(
      description: folder["description"] as? String ?? "",
      paper: folder["paper"] as? String ?? "dotted",
      coverColor: folder["coverColor"] as? String ?? "#24324A",
      coverStyle: folder["coverStyle"] as? String ?? "classic",
      tags: folder["tags"] as? [String] ?? [])
  }

  static func settingFavorite(
    in data: Data?,
    path: [String],
    favorite: Bool
  ) throws -> Data {
    var root = try object(from: data)
    var notes = root["notes"] as? [String: Any] ?? [:]
    let key = path.joined(separator: "/")
    var note = notes[key] as? [String: Any] ?? [
      "favorite": false,
      "tags": [String](),
      "description": "",
    ]
    note["favorite"] = favorite
    if note["tags"] == nil { note["tags"] = [String]() }
    if note["description"] == nil { note["description"] = "" }
    notes[key] = note
    root["notes"] = notes
    return try encoded(root)
  }

  static func settingNoteDetails(
    in data: Data?,
    path: [String],
    details: LibraryNoteDetails
  ) throws -> Data {
    var root = try object(from: data)
    registerTags(details.tags, in: &root)
    var notes = root["notes"] as? [String: Any] ?? [:]
    notes[path.joined(separator: "/")] = [
      "favorite": details.favorite,
      "tags": normalizedTags(details.tags),
      "description": details.description,
    ]
    root["notes"] = notes
    return try encoded(root)
  }

  static func settingFolderDetails(
    in data: Data?,
    path: [String],
    details: LibraryFolderDetails
  ) throws -> Data {
    var root = try object(from: data)
    registerTags(details.tags, in: &root)
    var folders = root["folders"] as? [String: Any] ?? [:]
    folders[path.joined(separator: "/")] = [
      "description": details.description,
      "paper": details.paper,
      "coverColor": details.coverColor,
      "coverStyle": details.coverStyle,
      "tags": normalizedTags(details.tags),
    ]
    root["folders"] = folders
    return try encoded(root)
  }

  static func addingTag(
    in data: Data?,
    name: String,
    color: String
  ) throws -> Data {
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty else {
      throw NotebookStorageError.invalidName("Enter a tag name.")
    }
    var root = try object(from: data)
    var values = root["tags"] as? [[String: Any]] ?? []
    guard !values.contains(where: { $0["name"] as? String == cleanName }) else {
      throw NotebookStorageError.invalidName("This tag name is already in use.")
    }
    values.append(["name": cleanName, "color": color])
    root["tags"] = values
    return try encoded(root)
  }

  static func moving(
    in data: Data?,
    from source: [String],
    to destination: [String]
  ) throws -> Data? {
    guard data != nil else { return nil }
    var root = try object(from: data)
    let sourceKey = source.joined(separator: "/")
    let destinationKey = destination.joined(separator: "/")

    func remap(_ values: [String: Any]) -> [String: Any] {
      var result: [String: Any] = [:]
      for (key, value) in values {
        let inside = key == sourceKey || key.hasPrefix("\(sourceKey)/")
        result[
          inside ? destinationKey + String(key.dropFirst(sourceKey.count)) : key
        ] = value
      }
      return result
    }

    func remapPath(_ path: [String]) -> [String] {
      guard path.count >= source.count,
        Array(path.prefix(source.count)) == source
      else { return path }
      return destination + Array(path.dropFirst(source.count))
    }

    root["notes"] = remap(root["notes"] as? [String: Any] ?? [:])
    root["folders"] = remap(root["folders"] as? [String: Any] ?? [:])

    if let templates = root["startingTemplates"] as? [[String: Any]] {
      root["startingTemplates"] = templates.map { template in
        var updated = template
        if let folder = template["folder"] as? [String] {
          updated["folder"] = remapPath(folder)
        }
        return updated
      }
    }

    if var draft = root["draft"] as? [String: Any],
      let folder = draft["folder"] as? [String]
    {
      draft["folder"] = remapPath(folder)
      root["draft"] = draft
    }

    return try encoded(root)
  }

  private static func normalizedTags(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return names.compactMap { name in
      let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty, seen.insert(value).inserted else { return nil }
      return value
    }
  }

  private static func registerTags(_ names: [String], in root: inout [String: Any]) {
    var values = root["tags"] as? [[String: Any]] ?? []
    var known = Set(values.compactMap { $0["name"] as? String })
    for name in normalizedTags(names) where known.insert(name).inserted {
      values.append([
        "name": name,
        "color": tagColors[values.count % tagColors.count],
      ])
    }
    root["tags"] = values
  }

  private static func object(from data: Data?) throws -> [String: Any] {
    guard let data else {
      return [
        "format": "math-notes-library",
        "version": 1,
        "tags": [[String: String]](),
        "notes": [String: Any](),
        "folders": [String: Any](),
        "startingTemplates": [[String: Any]](),
      ]
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw NotebookStorageError.coordinationFailed(name)
    }
    return root
  }

  private static func encoded(_ root: [String: Any]) throws -> Data {
    enum Context {
      case root
      case tags
      case tag
      case notes
      case note
      case folders
      case folder
      case templates
      case template
      case draft
      case generic
    }

    func preferredKeys(_ context: Context) -> [String] {
      switch context {
      case .root:
        ["format", "version", "tags", "notes", "folders", "startingTemplates", "draft"]
      case .tag:
        ["name", "color"]
      case .note:
        ["favorite", "tags", "description"]
      case .folder:
        ["description", "paper", "coverColor", "coverStyle", "tags"]
      case .template:
        ["name", "folder", "paper", "pageSize", "orientation", "tags"]
      case .draft:
        ["folder", "title", "template", "tags", "pageSize", "orientation"]
      case .tags, .notes, .folders, .templates, .generic:
        []
      }
    }

    func childContext(_ context: Context, key: String) -> Context {
      switch (context, key) {
      case (.root, "tags"): .tags
      case (.root, "notes"): .notes
      case (.root, "folders"): .folders
      case (.root, "startingTemplates"): .templates
      case (.root, "draft"): .draft
      case (.notes, _): .note
      case (.folders, _): .folder
      default: .generic
      }
    }

    func elementContext(_ context: Context) -> Context {
      switch context {
      case .tags: .tag
      case .templates: .template
      default: .generic
      }
    }

    func scalar(_ value: Any) throws -> String {
      let data = try JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .withoutEscapingSlashes])
      return String(decoding: data, as: UTF8.self)
    }

    func render(_ value: Any, context: Context, indent: Int) throws -> String {
      if let object = value as? [String: Any] {
        guard !object.isEmpty else { return "{}" }
        let preferred = preferredKeys(context)
        let known = preferred.filter { object[$0] != nil }
        let extras = object.keys.filter { !preferred.contains($0) }.sorted()
        let keys = known + extras
        let childIndent = indent + 2
        let prefix = String(repeating: " ", count: childIndent)
        let suffix = String(repeating: " ", count: indent)
        let lines = try keys.map { key in
          let child = try render(
            object[key]!,
            context: childContext(context, key: key),
            indent: childIndent)
          return "\(prefix)\(try scalar(key)): \(child)"
        }
        return "{\n\(lines.joined(separator: ",\n"))\n\(suffix)}"
      }

      if let array = value as? [Any] {
        guard !array.isEmpty else { return "[]" }
        let childIndent = indent + 2
        let prefix = String(repeating: " ", count: childIndent)
        let suffix = String(repeating: " ", count: indent)
        let context = elementContext(context)
        let lines = try array.map {
          "\(prefix)\(try render($0, context: context, indent: childIndent))"
        }
        return "[\n\(lines.joined(separator: ",\n"))\n\(suffix)]"
      }

      return try scalar(value)
    }

    var data = Data(try render(root, context: .root, indent: 0).utf8)
    data.append(0x0A)
    return data
  }
}

enum NotebookStorageError: LocalizedError {
  case cannotAccessRoot
  case coordinationFailed(String)
  case invalidName(String)
  case entryExists(String)
  case missingTemplate(String)

  var errorDescription: String? {
    switch self {
    case .cannotAccessRoot:
      return "Math Notes no longer has access to the selected notes folder."
    case let .coordinationFailed(path):
      return "File coordination did not provide access to \(path)."
    case let .invalidName(message):
      return message
    case let .entryExists(name):
      return "\(name) already exists in that folder."
    case let .missingTemplate(name):
      return "Template \(name) has no pages/0001.svg."
    }
  }
}

private final class RootFilePresenter: NSObject, NSFilePresenter {
  let presentedItemURL: URL?
  let presentedItemOperationQueue: OperationQueue = .main
  var onChange: (() -> Void)?

  init(url: URL) {
    presentedItemURL = url
  }

  func presentedItemDidChange() {
    onChange?()
  }

  func presentedSubitemDidAppear(at url: URL) {
    onChange?()
  }

  func presentedSubitemDidChange(at url: URL) {
    onChange?()
  }
}

final class NotesRootAccess {
  private static let bookmarkKey = "notes-root-bookmark"

  let url: URL
  var onChange: (() -> Void)?

  private let presenter: RootFilePresenter
  private var accessing = true
  private var thumbnailCache: [String: (stamp: String, data: Data)] = [:]

  init(selectedURL: URL) throws {
    guard selectedURL.startAccessingSecurityScopedResource() else {
      throw NotebookStorageError.cannotAccessRoot
    }

    do {
      try Self.saveBookmark(for: selectedURL)
    } catch {
      selectedURL.stopAccessingSecurityScopedResource()
      throw error
    }

    url = selectedURL
    presenter = RootFilePresenter(url: selectedURL)
    presenter.onChange = { [weak self] in self?.onChange?() }
    NSFileCoordinator.addFilePresenter(presenter)
  }

  private init(restoredURL: URL, refreshBookmark: Bool) throws {
    guard restoredURL.startAccessingSecurityScopedResource() else {
      throw NotebookStorageError.cannotAccessRoot
    }

    do {
      if refreshBookmark {
        try Self.saveBookmark(for: restoredURL)
      }
    } catch {
      restoredURL.stopAccessingSecurityScopedResource()
      throw error
    }

    url = restoredURL
    presenter = RootFilePresenter(url: restoredURL)
    presenter.onChange = { [weak self] in self?.onChange?() }
    NSFileCoordinator.addFilePresenter(presenter)
  }

  deinit {
    NSFileCoordinator.removeFilePresenter(presenter)
    if accessing {
      url.stopAccessingSecurityScopedResource()
    }
  }

  static func restore() -> NotesRootAccess? {
    guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
      return nil
    }

    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        bookmarkDataIsStale: &stale)
      return try NotesRootAccess(restoredURL: url, refreshBookmark: stale)
    } catch {
      return nil
    }
  }

  static func forgetSavedRoot() {
    UserDefaults.standard.removeObject(forKey: bookmarkKey)
  }

  func notebooks() throws -> [NotebookReference] {
    try coordinatedRead(at: url) { root in
      let fileManager = FileManager.default
      var notebooks: [NotebookReference] = []

      func visit(_ directory: URL, path: [String]) throws {
        let children = try fileManager.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])

        for child in children {
          let name = child.lastPathComponent
          guard !name.hasPrefix(".") else { continue }
          guard try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            continue
          }

          if fileManager.fileExists(
            atPath: child.appendingPathComponent("notebook.json").path)
          {
            notebooks.append(NotebookReference(path: path + [name]))
          } else {
            try visit(child, path: path + [name])
          }
        }
      }

      try visit(root, path: [])
      return notebooks.sorted {
        $0.id.localizedStandardCompare($1.id) == .orderedAscending
      }
    }
  }

  func folders() throws -> [FolderReference] {
    try coordinatedRead(at: url) { root in
      let fileManager = FileManager.default
      var folders = [FolderReference(path: [])]

      func visit(_ directory: URL, path: [String]) throws {
        let children = try fileManager.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])
        for child in children {
          let name = child.lastPathComponent
          guard !name.hasPrefix("."),
            try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
          else { continue }
          if fileManager.fileExists(
            atPath: child.appendingPathComponent("notebook.json").path)
          {
            continue
          }
          let childPath = path + [name]
          folders.append(FolderReference(path: childPath))
          try visit(child, path: childPath)
        }
      }

      try visit(root, path: [])
      return folders.sorted { left, right in
        if left.path.isEmpty { return true }
        if right.path.isEmpty { return false }
        return left.id.localizedStandardCompare(right.id) == .orderedAscending
      }
    }
  }

  func library(
    in parent: FolderReference,
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    try coordinatedRead(at: url) { root in
      let directory = parent.path.reduce(root) { partial, component in
        partial.appendingPathComponent(component, isDirectory: true)
      }
      let favoritePaths = try LibraryMetadataFile.favoritePaths(
        in: LibraryMetadataFile.read(at: root))
      let children = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
      var folders: [LibraryFolderItem] = []
      var notebooks: [LibraryNotebookItem] = []

      for child in children {
        let name = child.lastPathComponent
        guard !name.hasPrefix("."),
          try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        else { continue }

        let path = parent.path + [name]
        if FileManager.default.fileExists(
          atPath: child.appendingPathComponent("notebook.json").path)
        {
          notebooks.append(
            LibraryNotebookItem(
              reference: NotebookReference(path: path),
              modified: try Self.notebookModification(at: child),
              favorite: favoritePaths.contains(path.joined(separator: "/"))))
        } else {
          folders.append(
            LibraryFolderItem(
              reference: FolderReference(path: path),
              modified: try Self.latestNotebookModification(in: child)))
        }
      }

      let nameOrder: (String, String) -> Bool = {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
      }
      let ascending = direction == .ascending
      switch sort {
      case .name:
        folders.sort {
          ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
        notebooks.sort {
          ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      case .modified:
        folders.sort {
          switch ($0.modified, $1.modified) {
          case let (left?, right?) where left != right:
            return ascending ? left < right : left > right
          default:
            return ascending
              ? nameOrder($0.reference.name, $1.reference.name)
              : nameOrder($1.reference.name, $0.reference.name)
          }
        }
        notebooks.sort {
          if $0.modified != $1.modified {
            return ascending ? $0.modified < $1.modified : $0.modified > $1.modified
          }
          return ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      }
      return LibraryListing(folders: folders, notebooks: notebooks)
    }
  }

  func searchLibrary(
    query: String,
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else {
      return try library(
        in: FolderReference(path: []),
        sort: sort,
        direction: direction)
    }

    return try coordinatedRead(at: url) { root in
      let fileManager = FileManager.default
      let favoritePaths = try LibraryMetadataFile.favoritePaths(
        in: LibraryMetadataFile.read(at: root))
      var folders: [LibraryFolderItem] = []
      var notebooks: [LibraryNotebookItem] = []

      func visit(_ directory: URL, path: [String]) throws {
        let children = try fileManager.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])

        for child in children {
          let name = child.lastPathComponent
          guard !name.hasPrefix("."),
            try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
          else { continue }

          let childPath = path + [name]
          if fileManager.fileExists(
            atPath: child.appendingPathComponent("notebook.json").path)
          {
            if name.localizedCaseInsensitiveContains(needle) {
              notebooks.append(
                LibraryNotebookItem(
                  reference: NotebookReference(path: childPath),
                  modified: try Self.notebookModification(at: child),
                  favorite: favoritePaths.contains(childPath.joined(separator: "/"))))
            }
          } else {
            if name.localizedCaseInsensitiveContains(needle) {
              folders.append(
                LibraryFolderItem(
                  reference: FolderReference(path: childPath),
                  modified: try Self.latestNotebookModification(in: child)))
            }
            try visit(child, path: childPath)
          }
        }
      }

      try visit(root, path: [])
      let nameOrder: (String, String) -> Bool = {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
      }
      let ascending = direction == .ascending
      switch sort {
      case .name:
        folders.sort {
          ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
        notebooks.sort {
          ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      case .modified:
        folders.sort {
          switch ($0.modified, $1.modified) {
          case let (left?, right?) where left != right:
            return ascending ? left < right : left > right
          default:
            return ascending
              ? nameOrder($0.reference.name, $1.reference.name)
              : nameOrder($1.reference.name, $0.reference.name)
          }
        }
        notebooks.sort {
          if $0.modified != $1.modified {
            return ascending ? $0.modified < $1.modified : $0.modified > $1.modified
          }
          return ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      }
      return LibraryListing(folders: folders, notebooks: notebooks)
    }
  }

  func allNotes(
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    try coordinatedRead(at: url) { root in
      let fileManager = FileManager.default
      let favoritePaths = try LibraryMetadataFile.favoritePaths(
        in: LibraryMetadataFile.read(at: root))
      var notebooks: [LibraryNotebookItem] = []

      func visit(_ directory: URL, path: [String]) throws {
        let children = try fileManager.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])

        for child in children {
          let name = child.lastPathComponent
          guard !name.hasPrefix("."),
            try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
          else { continue }

          let childPath = path + [name]
          if fileManager.fileExists(
            atPath: child.appendingPathComponent("notebook.json").path)
          {
            notebooks.append(
            LibraryNotebookItem(
              reference: NotebookReference(path: childPath),
              modified: try Self.notebookModification(at: child),
              favorite: favoritePaths.contains(childPath.joined(separator: "/"))))
          } else {
            try visit(child, path: childPath)
          }
        }
      }

      try visit(root, path: [])
      let nameOrder: (String, String) -> Bool = {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
      }
      let ascending = direction == .ascending
      switch sort {
      case .name:
        notebooks.sort {
          ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      case .modified:
        notebooks.sort {
          if $0.modified != $1.modified {
            return ascending ? $0.modified < $1.modified : $0.modified > $1.modified
          }
          return ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      }
      return LibraryListing(folders: [], notebooks: notebooks)
    }
  }

  func favoriteNotes(
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    let listing = try allNotes(sort: sort, direction: direction)
    return LibraryListing(
      folders: [],
      notebooks: listing.notebooks.filter(\.favorite))
  }

  func taggedLibrary(
    tag: String,
    query: String,
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let allNotebooks = try allNotes(sort: sort, direction: direction).notebooks
    var notebooks: [LibraryNotebookItem] = []
    for item in allNotebooks {
      let details = try noteDetails(for: item.reference)
      guard details.tags.contains(tag) else { continue }
      if needle.isEmpty ||
        item.reference.name.localizedCaseInsensitiveContains(needle) ||
        details.description.localizedCaseInsensitiveContains(needle) ||
        details.tags.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
      {
        notebooks.append(item)
      }
    }

    var folderItems: [LibraryFolderItem] = []
    for reference in try folders() where !reference.path.isEmpty {
      let details = try folderDetails(for: reference)
      guard details.tags.contains(tag) else { continue }
      let descendantNames = allNotebooks.lazy
        .filter {
          $0.reference.path.count > reference.path.count &&
          Array($0.reference.path.prefix(reference.path.count)) == reference.path
        }
        .map(\.reference.name)
      guard needle.isEmpty ||
        reference.name.localizedCaseInsensitiveContains(needle) ||
        details.description.localizedCaseInsensitiveContains(needle) ||
        details.tags.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) ||
        descendantNames.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
      else { continue }

      let directory = urlForPath(reference.path)
      folderItems.append(
        LibraryFolderItem(
          reference: reference,
          modified: try coordinatedRead(at: directory) {
            try Self.latestNotebookModification(in: $0)
          }))
    }

    let nameOrder: (String, String) -> Bool = {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
    let ascending = direction == .ascending
    switch sort {
    case .name:
      folderItems.sort {
        ascending
          ? nameOrder($0.reference.name, $1.reference.name)
          : nameOrder($1.reference.name, $0.reference.name)
      }
    case .modified:
      folderItems.sort {
        switch ($0.modified, $1.modified) {
        case let (left?, right?) where left != right:
          return ascending ? left < right : left > right
        default:
          return ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      }
    }
    return LibraryListing(folders: folderItems, notebooks: notebooks)
  }

  func trashNotes(
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    try coordinatedRead(at: url) { root in
      let trash = root.appendingPathComponent(".trash", isDirectory: true)
      guard FileManager.default.fileExists(atPath: trash.path) else {
        return LibraryListing(folders: [], notebooks: [])
      }

      let fileManager = FileManager.default
      let favoritePaths = try LibraryMetadataFile.favoritePaths(
        in: LibraryMetadataFile.read(at: root))
      var notebooks: [LibraryNotebookItem] = []

      func visit(_ directory: URL, path: [String]) throws {
        let children = try fileManager.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])
        for child in children {
          guard try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            continue
          }
          let childPath = path + [child.lastPathComponent]
          if fileManager.fileExists(
            atPath: child.appendingPathComponent("notebook.json").path)
          {
            notebooks.append(
              LibraryNotebookItem(
                reference: NotebookReference(path: childPath),
                modified: try Self.notebookModification(at: child),
                favorite: favoritePaths.contains(childPath.joined(separator: "/"))))
          } else {
            try visit(child, path: childPath)
          }
        }
      }

      try visit(trash, path: [".trash"])
      let nameOrder: (String, String) -> Bool = {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
      }
      let ascending = direction == .ascending
      switch sort {
      case .name:
        notebooks.sort {
          ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      case .modified:
        notebooks.sort {
          if $0.modified != $1.modified {
            return ascending ? $0.modified < $1.modified : $0.modified > $1.modified
          }
          return ascending
            ? nameOrder($0.reference.name, $1.reference.name)
            : nameOrder($1.reference.name, $0.reference.name)
        }
      }
      return LibraryListing(folders: [], notebooks: notebooks)
    }
  }

  func setFavorite(_ favorite: Bool, for reference: NotebookReference) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let updated = try LibraryMetadataFile.settingFavorite(
        in: LibraryMetadataFile.read(at: root),
        path: reference.path,
        favorite: favorite)
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
    }
  }

  func libraryTags() throws -> [LibraryTag] {
    try coordinatedRead(at: url) { root in
      try LibraryMetadataFile.tags(in: LibraryMetadataFile.read(at: root))
    }
  }

  func noteDetails(for reference: NotebookReference) throws -> LibraryNoteDetails {
    try coordinatedRead(at: url) { root in
      try LibraryMetadataFile.noteDetails(
        in: LibraryMetadataFile.read(at: root),
        path: reference.path)
    }
  }

  func folderDetails(for reference: FolderReference) throws -> LibraryFolderDetails {
    try coordinatedRead(at: url) { root in
      try LibraryMetadataFile.folderDetails(
        in: LibraryMetadataFile.read(at: root),
        path: reference.path)
    }
  }

  func saveNoteDetails(_ details: LibraryNoteDetails, for reference: NotebookReference) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let updated = try LibraryMetadataFile.settingNoteDetails(
        in: LibraryMetadataFile.read(at: root),
        path: reference.path,
        details: details)
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
    }
  }

  func saveFolderDetails(_ details: LibraryFolderDetails, for reference: FolderReference) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let updated = try LibraryMetadataFile.settingFolderDetails(
        in: LibraryMetadataFile.read(at: root),
        path: reference.path,
        details: details)
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
    }
  }

  func addLibraryTag(name: String, color: String) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let updated = try LibraryMetadataFile.addingTag(
        in: LibraryMetadataFile.read(at: root),
        name: name,
        color: color)
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
    }
  }

  func createFolder(parent: FolderReference, name: String) throws -> FolderReference {
    let cleanName = try validatedLibraryName(name)
    let path = parent.path + [cleanName]
    try createNewDirectory(path: path, name: cleanName)
    return FolderReference(path: path)
  }

  func moveEntry(
    path: [String],
    toParent parent: FolderReference,
    name: String
  ) throws -> [String] {
    guard !path.isEmpty else {
      throw NotebookStorageError.invalidName("The notes root cannot be moved.")
    }
    let cleanName = try validatedLibraryName(name)
    let destinationPath = parent.path + [cleanName]
    if destinationPath == path { return path }

    if parent.path.count >= path.count,
      Array(parent.path.prefix(path.count)) == path
    {
      throw NotebookStorageError.invalidName("A folder cannot move into itself.")
    }

    let source = urlForPath(path)
    let destination = urlForPath(destinationPath)
    try coordinatedMove(from: source, to: destination, name: cleanName)
    try moveLibraryMetadata(from: path, to: destinationPath)
    thumbnailCache.removeAll()
    return destinationPath
  }

  func moveToTrash(path: [String]) throws -> [String] {
    guard let name = path.last else {
      throw NotebookStorageError.invalidName("The notes root cannot be moved to trash.")
    }
    try ensureDirectory(path: [".trash"])
    let taken = Set(try entryNames(at: [".trash"]))
    var target = name
    var suffix = 2
    while taken.contains(target) {
      target = "\(name) \(suffix)"
      suffix += 1
    }
    return try moveEntry(
      path: path,
      toParent: FolderReference(path: [".trash"]),
      name: target)
  }

  @MainActor
  func thumbnail(_ reference: NotebookReference) throws -> Data? {
    let notebookURL = urlForNotebook(reference)
    let stamp = try coordinatedRead(at: notebookURL) { coordinatedNotebook in
      try Self.thumbnailStamp(at: coordinatedNotebook)
    }
    guard let stamp else { return nil }
    if let cached = thumbnailCache[reference.id], cached.stamp == stamp {
      return cached.data
    }

    let document = try load(reference)
    let data = try document.pagePNG(index: 0, width: 240)
    thumbnailCache[reference.id] = (stamp: stamp, data: data)
    return data
  }


  @MainActor
  func penLibrary() throws -> EditorPenLibrary {
    try ensurePenFile()
    let fileURL = url.appendingPathComponent(".pens.json")
    let data = try coordinatedRead(at: fileURL) { coordinatedURL in
      try Data(contentsOf: coordinatedURL)
    }
    return try EditorPenLibrary(json: data)
  }

  @MainActor
  func savePenLibrary(_ library: EditorPenLibrary) throws {
    try ensurePenFile()
    let data = try library.json()
    let fileURL = url.appendingPathComponent(".pens.json")
    try coordinatedWrite(at: fileURL, options: .forReplacing) { coordinatedURL in
      try data.write(to: coordinatedURL, options: .atomic)
    }
  }

  @MainActor
  private func ensurePenFile() throws {
    guard try !itemExists(at: [".pens.json"]) else { return }
    let data = try EditorPenLibrary.defaultJSON()
    try coordinatedWrite(at: url, options: .forMerging) { coordinatedRoot in
      let fileURL = coordinatedRoot.appendingPathComponent(".pens.json")
      guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
      try data.write(to: fileURL, options: .atomic)
    }
  }
  @MainActor
  func ensureBuiltinTemplates() throws {
    for name in try EngineDocument.builtinTemplateNames() {
      let reference = NotebookReference(path: [".templates", name])
      if try itemExists(at: reference.path + ["notebook.json"]) { continue }
      try ensureDirectory(path: reference.path)
      let document = try EngineDocument.builtinTemplate(
        name: name,
        seed: UInt64.random(in: 1...UInt64.max))
      try save(document, notebook: reference)
    }
  }

  @MainActor
  func templateNames() throws -> [String] {
    try ensureBuiltinTemplates()
    let templatesURL = url.appendingPathComponent(".templates", isDirectory: true)
    return try coordinatedRead(at: templatesURL) { directory in
      try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
        .filter { candidate in
          (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
            FileManager.default.fileExists(
              atPath: candidate.appendingPathComponent("notebook.json").path)
        }
        .map(\.lastPathComponent)
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
  }

  func templateName(for reference: NotebookReference) throws -> String? {
    let indexURL = urlForNotebook(reference).appendingPathComponent("notebook.json")
    return try coordinatedRead(at: indexURL) { coordinatedURL in
      let data = try Data(contentsOf: coordinatedURL)
      return try JSONDecoder().decode(NotebookIndex.self, from: data).template
    }
  }

  @MainActor
  func applyTemplate(name: String, to document: EngineDocument) throws {
    try ensureBuiltinTemplates()
    let pageURL = url
      .appendingPathComponent(".templates", isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("0001.svg")
    guard try itemExists(at: [".templates", name, "pages", "0001.svg"]) else {
      throw NotebookStorageError.missingTemplate(name)
    }
    let page = try coordinatedRead(at: pageURL) { try Data(contentsOf: $0) }
    try document.setTemplate(name: name, page: page)
  }

  @MainActor
  func createNote(
    title: String,
    parent: FolderReference,
    template: String,
    pageSize: InkPageSize,
    orientation: InkOrientation
  ) throws -> (NotebookReference, EngineDocument) {
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      throw NotebookStorageError.invalidName("Enter a note title.")
    }
    guard !name.contains("/"), !name.contains("\\"), !name.hasPrefix(".") else {
      throw NotebookStorageError.invalidName("A note title cannot start with a dot or contain / or \\.")
    }

    try ensureBuiltinTemplates()
    let reference = NotebookReference(path: parent.path + [name])
    let notebookURL = urlForNotebook(reference)
    let templatePageURL = url
      .appendingPathComponent(".templates", isDirectory: true)
      .appendingPathComponent(template, isDirectory: true)
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("0001.svg")
    guard try itemExists(at: [".templates", template, "pages", "0001.svg"]) else {
      throw NotebookStorageError.missingTemplate(template)
    }
    let page = try coordinatedRead(at: templatePageURL) { try Data(contentsOf: $0) }
    let document = try EngineDocument.createFromTemplate(
      seed: UInt64.random(in: 1...UInt64.max),
      name: template,
      page: page,
      pageSize: pageSize,
      orientation: orientation)

    try createNewDirectory(path: reference.path, name: name)
    do {
      try save(document, notebook: reference)
      return (reference, document)
    } catch {
      try? coordinatedWrite(at: notebookURL, options: .forDeleting) { coordinatedURL in
        if FileManager.default.fileExists(atPath: coordinatedURL.path) {
          try FileManager.default.removeItem(at: coordinatedURL)
        }
      }
      throw error
    }
  }

  @MainActor
  func loadClippings() throws -> (NotebookReference, EngineDocument) {
    let reference = NotebookReference(path: [".clippings"])
    if try itemExists(at: [".clippings", "notebook.json"]) {
      return (reference, try load(reference))
    }

    try ensureDirectory(path: reference.path)
    let document = EngineDocument(seed: UInt64.random(in: 1...UInt64.max))
    try document.deletePage(at: 0)

    let outline = "fill=\"none\" stroke=\"#000000\" stroke-width=\"1.4\""
    let shapes = [
      "<ellipse cx=\"30\" cy=\"30\" rx=\"27\" ry=\"27\" \(outline)/>",
      "<rect x=\"3\" y=\"3\" width=\"54\" height=\"54\" \(outline)/>",
      "<polygon points=\"30,3 57,57 3,57\" \(outline)/>",
      "<polygon points=\"3,30 16.5,6.6 43.5,6.6 57,30 43.5,53.4 16.5,53.4\" \(outline)/>",
    ]
    for shape in shapes {
      try document.addClipping(
        svg: "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"60\" height=\"60\"><g id=\"clipping\">\(shape)</g></svg>")
    }
    try save(document, notebook: reference)
    return (reference, document)
  }

  @MainActor
  func clippingPreviews(width: Int32 = 240) throws -> [(id: String, png: Data)] {
    let (reference, document) = try loadClippings()
    let ids = try clippingPageIDs(reference)
    let pageCount = try document.pageCount()
    guard ids.count == pageCount else {
      throw EngineDocumentError.operation(
        "List clippings", "The clipping index changed while it was being read")
    }
    return try ids.enumerated().map {
      (id: $0.element, png: try document.pagePNG(index: $0.offset, width: width))
    }
  }

  @MainActor
  func addClipping(svg: String) throws {
    let (reference, document) = try loadClippings()
    try document.addClipping(svg: svg)
    try save(document, notebook: reference)
  }

  @MainActor
  func clippingSVG(id: String) throws -> String {
    let (reference, document) = try loadClippings()
    return try document.clippingSVG(index: clippingIndex(id, reference: reference))
  }

  @MainActor
  func moveClipping(id: String, by offset: Int) throws {
    let (reference, document) = try loadClippings()
    let index = try clippingIndex(id, reference: reference)
    let target = index + offset
    let pageCount = try document.pageCount()
    guard target >= 0, target < pageCount else { return }
    try document.movePage(from: index, to: target)
    try save(document, notebook: reference)
  }

  @MainActor
  func deleteClipping(id: String) throws {
    let (reference, document) = try loadClippings()
    try document.deletePage(at: clippingIndex(id, reference: reference))
    try save(document, notebook: reference)
  }

  private func clippingPageIDs(_ reference: NotebookReference) throws -> [String] {
    let indexURL = urlForNotebook(reference).appendingPathComponent("notebook.json")
    let data = try coordinatedRead(at: indexURL) { try Data(contentsOf: $0) }
    let pages = try JSONDecoder().decode(NotebookIndex.self, from: data).pages ?? []
    return try pages.map {
      guard let id = $0.id, !id.isEmpty else {
        throw EngineDocumentError.operation("List clippings", "A clipping has no stable page id")
      }
      return id
    }
  }

  private func clippingIndex(_ id: String, reference: NotebookReference) throws -> Int {
    guard let index = try clippingPageIDs(reference).firstIndex(of: id) else {
      throw EngineDocumentError.operation(
        "Read clipping", "This clipping was removed. Refresh the panel.")
    }
    return index
  }

  @MainActor
  func load(_ reference: NotebookReference) throws -> EngineDocument {
    let notebookURL = urlForNotebook(reference)
    let snapshot = try coordinatedRead(at: notebookURL) { coordinatedURL in
      try Self.readSnapshot(at: coordinatedURL)
    }

    let document = EngineDocument(seed: UInt64.random(in: 1...UInt64.max))
    try document.loadNotebook(snapshot.notebookJSON)
    for file in snapshot.pages {
      try document.loadPage(path: file.path, data: file.data)
    }
    for file in snapshot.assets {
      try document.loadAsset(path: file.path, data: file.data)
    }

    if let template = snapshot.template {
      let pageURL = url
        .appendingPathComponent(".templates", isDirectory: true)
        .appendingPathComponent(template, isDirectory: true)
        .appendingPathComponent("pages", isDirectory: true)
        .appendingPathComponent("0001.svg")
      if FileManager.default.fileExists(atPath: pageURL.path) {
        let page = try coordinatedRead(at: pageURL) { try Data(contentsOf: $0) }
        try document.setTemplate(name: template, page: page)
      }
    }

    return document
  }

  @MainActor
  func save(_ document: EngineDocument, notebook reference: NotebookReference) throws {
    let changes = orderedNotebookChanges(try document.dirtyFiles())
    guard !changes.isEmpty else { return }

    let notebookURL = urlForNotebook(reference)
    for change in changes {
      try ensureParentDirectory(for: change.path, notebookURL: notebookURL)
      let target = change.path.split(separator: "/").reduce(notebookURL) {
        $0.appendingPathComponent(String($1))
      }

      switch change.kind {
      case let .write(data):
        try coordinatedWrite(at: target, options: .forReplacing) { coordinatedURL in
          try data.write(to: coordinatedURL, options: .atomic)
        }
      case .delete:
        guard FileManager.default.fileExists(atPath: target.path) else { continue }
        try coordinatedWrite(at: target, options: .forDeleting) { coordinatedURL in
          try FileManager.default.removeItem(at: coordinatedURL)
        }
      }
    }

    try document.markSaved()
  }

  private func entryNames(at path: [String]) throws -> [String] {
    let directory = urlForPath(path)
    return try coordinatedRead(at: directory) { coordinatedDirectory in
      try FileManager.default.contentsOfDirectory(atPath: coordinatedDirectory.path)
    }
  }

  private func moveLibraryMetadata(from source: [String], to destination: [String]) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      guard let current = try LibraryMetadataFile.read(at: root),
        let updated = try LibraryMetadataFile.moving(
          in: current,
          from: source,
          to: destination)
      else { return }
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
    }
  }

  private func coordinatedMove(from source: URL, to destination: URL, name: String) throws {
    let destinationParent = destination.deletingLastPathComponent()
    var coordinatorError: NSError?
    var result: Result<Void, Error>?
    let coordinator = NSFileCoordinator()
    coordinator.coordinate(
      writingItemAt: source,
      options: .forMoving,
      writingItemAt: destinationParent,
      options: .forMerging,
      error: &coordinatorError
    ) { coordinatedSource, coordinatedParent in
      result = Result {
        let coordinatedDestination = coordinatedParent
          .appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: coordinatedDestination.path) else {
          throw NotebookStorageError.entryExists(name)
        }
        try FileManager.default.moveItem(at: coordinatedSource, to: coordinatedDestination)
      }
    }

    if let coordinatorError { throw coordinatorError }
    guard let result else {
      throw NotebookStorageError.coordinationFailed(source.path)
    }
    try result.get()
  }

  private func itemExists(at path: [String]) throws -> Bool {
    try coordinatedRead(at: url) { root in
      let target = path.reduce(root) { partial, component in
        partial.appendingPathComponent(component)
      }
      return FileManager.default.fileExists(atPath: target.path)
    }
  }

  private func createNewDirectory(path: [String], name: String) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let directory = path.reduce(root) { partial, component in
        partial.appendingPathComponent(component, isDirectory: true)
      }
      guard !FileManager.default.fileExists(atPath: directory.path) else {
        throw NotebookStorageError.entryExists(name)
      }
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false)
    }
  }

  private func ensureDirectory(path: [String]) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let directory = path.reduce(root) { partial, component in
        partial.appendingPathComponent(component, isDirectory: true)
      }
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true)
    }
  }

  private static func saveBookmark(for url: URL) throws {
    let data = try url.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    UserDefaults.standard.set(data, forKey: bookmarkKey)
  }

  private func urlForPath(_ path: [String]) -> URL {
    path.reduce(url) {
      $0.appendingPathComponent($1, isDirectory: true)
    }
  }

  private func urlForNotebook(_ reference: NotebookReference) -> URL {
    urlForPath(reference.path)
  }

  private func ensureParentDirectory(for path: String, notebookURL: URL) throws {
    let components = path.split(separator: "/").dropLast()
    guard !components.isEmpty else { return }

    var expected = notebookURL
    for component in components {
      expected.appendPathComponent(String(component), isDirectory: true)
    }
    guard !FileManager.default.fileExists(atPath: expected.path) else { return }

    try coordinatedWrite(at: notebookURL, options: .forMerging) { coordinatedNotebook in
      var directory = coordinatedNotebook
      for component in components {
        directory.appendPathComponent(String(component), isDirectory: true)
      }
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true)
    }
  }

  private func coordinatedRead<T>(
    at target: URL,
    _ body: (URL) throws -> T
  ) throws -> T {
    var coordinatorError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator().coordinate(
      readingItemAt: target,
      options: [],
      error: &coordinatorError
    ) { coordinatedURL in
      result = Result { try body(coordinatedURL) }
    }

    if let coordinatorError { throw coordinatorError }
    guard let result else {
      throw NotebookStorageError.coordinationFailed(target.path)
    }
    return try result.get()
  }

  private func coordinatedWrite<T>(
    at target: URL,
    options: NSFileCoordinator.WritingOptions,
    _ body: (URL) throws -> T
  ) throws -> T {
    var coordinatorError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator().coordinate(
      writingItemAt: target,
      options: options,
      error: &coordinatorError
    ) { coordinatedURL in
      result = Result { try body(coordinatedURL) }
    }

    if let coordinatorError { throw coordinatorError }
    guard let result else {
      throw NotebookStorageError.coordinationFailed(target.path)
    }
    return try result.get()
  }

  private struct StoredFile {
    let path: String
    let data: Data
  }

  private struct Snapshot {
    let notebookJSON: Data
    let pages: [StoredFile]
    let assets: [StoredFile]
    let template: String?
  }

  private struct NotebookIndex: Decodable {
    struct Page: Decodable {
      let id: String?
      let file: String
    }

    let template: String?
    let pages: [Page]?
  }

  private final class PageImageParser: NSObject, XMLParserDelegate {
    var references: [String] = []

    func parser(
      _ parser: XMLParser,
      didStartElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?,
      attributes attributeDict: [String: String]
    ) {
      guard elementName == "image" else { return }
      if let href = attributeDict["href"] ?? attributeDict["xlink:href"] {
        references.append(href)
      }
    }
  }

  private static func thumbnailStamp(at notebookURL: URL) throws -> String? {
    let indexURL = notebookURL.appendingPathComponent("notebook.json")
    let indexData = try Data(contentsOf: indexURL)
    let index = try JSONDecoder().decode(NotebookIndex.self, from: indexData)
    guard let firstPage = index.pages?.first?.file else { return nil }

    let pageURL = firstPage.split(separator: "/").reduce(notebookURL) { partial, component in
      partial.appendingPathComponent(String(component))
    }
    let pageData = try Data(contentsOf: pageURL)
    var stamps = [try fileStamp(path: firstPage, url: pageURL)]

    let imageParser = PageImageParser()
    let parser = XMLParser(data: pageData)
    parser.delegate = imageParser
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else {
      if let error = parser.parserError { throw error }
      return stamps.joined(separator: "\n")
    }

    let pageDirectory = pageURL.deletingLastPathComponent()
    let rootPath = notebookURL.standardizedFileURL.path
    let assets = imageParser.references.compactMap { href -> (String, URL)? in
      guard let components = URLComponents(string: href), components.scheme == nil,
        let resolved = URL(string: href, relativeTo: pageDirectory)?.standardizedFileURL
      else { return nil }
      let assetPath = resolved.path
      guard assetPath.hasPrefix(rootPath + "/") else { return nil }
      let relative = String(assetPath.dropFirst(rootPath.count + 1))
      return (relative, resolved)
    }

    var seen: Set<String> = []
    for (path, assetURL) in assets.sorted(by: { $0.0 < $1.0 }) {
      guard seen.insert(path).inserted,
        FileManager.default.fileExists(atPath: assetURL.path)
      else { continue }
      stamps.append(try fileStamp(path: path, url: assetURL))
    }
    return stamps.joined(separator: "\n")
  }

  private static func fileStamp(path: String, url: URL) throws -> String {
    let values = try url.resourceValues(
      forKeys: [.contentModificationDateKey, .fileSizeKey])
    return "\(path):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? -1)"
  }

  private static func notebookModification(at notebookURL: URL) throws -> Date {
    let fileManager = FileManager.default
    var latest =
      try notebookURL
        .appendingPathComponent("notebook.json")
        .resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate ?? .distantPast

    let pagesURL = notebookURL.appendingPathComponent("pages", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: pagesURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return latest
    }

    for page in try fileManager.contentsOfDirectory(
      at: pagesURL,
      includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles])
    {
      let values = try page.resourceValues(
        forKeys: [.isRegularFileKey, .contentModificationDateKey])
      guard values.isRegularFile == true, let modified = values.contentModificationDate else {
        continue
      }
      if modified > latest { latest = modified }
    }
    return latest
  }

  private static func latestNotebookModification(in directory: URL) throws -> Date? {
    let fileManager = FileManager.default
    var latest: Date?
    for child in try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])
    {
      guard !child.lastPathComponent.hasPrefix("."),
        try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
      else { continue }

      let candidate: Date?
      if fileManager.fileExists(
        atPath: child.appendingPathComponent("notebook.json").path)
      {
        candidate = try notebookModification(at: child)
      } else {
        candidate = try latestNotebookModification(in: child)
      }
      if let candidate, latest == nil || candidate > latest! {
        latest = candidate
      }
    }
    return latest
  }

  private static func readSnapshot(at notebookURL: URL) throws -> Snapshot {
    let notebookJSON = try Data(
      contentsOf: notebookURL.appendingPathComponent("notebook.json"))
    let template = try? JSONDecoder().decode(
      NotebookIndex.self,
      from: notebookJSON).template

    return Snapshot(
      notebookJSON: notebookJSON,
      pages: try readFiles(
        in: notebookURL.appendingPathComponent("pages", isDirectory: true),
        prefix: "pages",
        extension: "svg"),
      assets: try readFiles(
        in: notebookURL.appendingPathComponent("assets", isDirectory: true),
        prefix: "assets",
        extension: nil),
      template: template ?? nil)
  }

  private static func readFiles(
    in directory: URL,
    prefix: String,
    extension wantedExtension: String?
  ) throws -> [StoredFile] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: directory.path,
      isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return []
    }

    return try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles])
      .filter { url in
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
          return false
        }
        return wantedExtension == nil || url.pathExtension == wantedExtension
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { url in
        StoredFile(
          path: "\(prefix)/\(url.lastPathComponent)",
          data: try Data(contentsOf: url))
      }
  }
}

func validatedLibraryName(_ name: String) throws -> String {
  let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    throw NotebookStorageError.invalidName("Enter a name.")
  }
  guard !trimmed.contains("/"), !trimmed.contains("\\") else {
    throw NotebookStorageError.invalidName("A name cannot contain / or \\.")
  }
  guard !trimmed.hasPrefix(".") else {
    throw NotebookStorageError.invalidName("A name cannot start with a dot.")
  }
  return trimmed
}

func orderedNotebookChanges(_ changes: [EngineFileChange]) -> [EngineFileChange] {
  func rank(_ change: EngineFileChange) -> Int {
    if case .delete = change.kind { return 3 }
    if change.path == "notebook.json" { return 2 }
    if change.path.hasPrefix("pages/") { return 1 }
    return 0
  }

  return changes.sorted {
    let left = rank($0)
    let right = rank($1)
    return left == right ? $0.path < $1.path : left < right
  }
}
