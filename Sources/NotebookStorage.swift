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
  let noteCount: Int
  let coverNote: NotebookReference?
  let details: LibraryFolderDetails

  var id: String { reference.id }
}

struct LibraryNotebookItem: Identifiable {
  let reference: NotebookReference
  let modified: Date
  let favorite: Bool
  let conflicts: Int
  let details: LibraryNoteDetails

  var id: String { reference.id }
}

struct LibraryListing {
  let folders: [LibraryFolderItem]
  let notebooks: [LibraryNotebookItem]
}

struct NotebookConflictCandidate: Equatable {
  let original: String
  let copy: String
  let provider: String
}

enum NotebookConflictChoice {
  case original
  case copy
  case both
}

enum NotebookConflictSource {
  case namedCopy(path: String)
  case fileVersion(NSFileVersion)
  case localDelete
}

struct NotebookConflict: Identifiable {
  let id: String
  let original: String
  let provider: String
  let originalBytes: Data?
  let copyBytes: Data?
  let left: Data?
  let right: Data?
  let leftSummary: String
  let rightSummary: String
  let notebook: Bool
  let page: Bool
  let source: NotebookConflictSource
}

private struct PendingDeleteConflictState {
  let pageIndex: Int?
  let pageID: String?
}

func notebookFileHasExternalChange(
  current: Data?,
  base: Data?,
  target: Data?
) -> Bool {
  current != base && current != target
}

func notebookConflictProvider(_ name: String) -> String {
  if name.contains("math-notes conflict") { return "Math Notes" }
  if name.contains(".sync-conflict-") { return "Syncthing" }
  if name.contains("'s conflicted copy") { return "Dropbox" }
  if name.contains("conflicted copy") || name.contains("case clash from") {
    return "Nextcloud"
  }
  if name.range(of: #" \(\d+\)\."#, options: .regularExpression) != nil {
    return "Google Drive"
  }
  if name.range(of: #" \d+\."#, options: .regularExpression) != nil {
    return "iCloud Drive"
  }
  if name.range(of: #"^[^-]+-.+\."#, options: .regularExpression) != nil {
    return "OneDrive"
  }
  return "Unlisted version"
}

func notebookConflictCandidates(
  listedPages: [String],
  rootFiles: [String],
  pageFiles: [String],
  assetFiles: [String]
) -> [NotebookConflictCandidate] {
  let listed = Set(listedPages)
  var result: [NotebookConflictCandidate] = []

  for name in pageFiles where name.hasSuffix(".svg") {
    let copy = "pages/\(name)"
    guard !listed.contains(copy),
      let original = listedPages.first(where: {
        copy.hasPrefix(String($0.dropLast(4)))
      })
    else { continue }
    result.append(
      NotebookConflictCandidate(
        original: original,
        copy: copy,
        provider: notebookConflictProvider(name)))
  }

  for name in rootFiles
    where name != "notebook.json" && name.hasPrefix("notebook") && name.hasSuffix(".json")
  {
    result.append(
      NotebookConflictCandidate(
        original: "notebook.json",
        copy: name,
        provider: notebookConflictProvider(name)))
  }

  let pattern = try! NSRegularExpression(
    pattern: #"^(.*?) \(math-notes conflict .*\)(\.[^.]+)$"#)
  for name in assetFiles {
    let range = NSRange(name.startIndex..<name.endIndex, in: name)
    guard let match = pattern.firstMatch(in: name, range: range),
      let stemRange = Range(match.range(at: 1), in: name),
      let extRange = Range(match.range(at: 2), in: name)
    else { continue }
    result.append(
      NotebookConflictCandidate(
        original: "assets/\(name[stemRange])\(name[extRange])",
        copy: "assets/\(name)",
        provider: "Math Notes"))
  }

  return result.sorted { $0.copy < $1.copy }
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

struct NewNoteDraft: Equatable {
  let folder: [String]
  let title: String
  let template: String
  let tags: [String]
  let pageSize: String?
  let orientation: String?
}

struct NewNoteStartingTemplate: Equatable, Identifiable {
  let name: String
  let folder: [String]
  let paper: String
  let pageSize: String
  let orientation: String?
  let tags: [String]

  var id: String { name }
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

  static func newNoteDraft(in data: Data?) throws -> NewNoteDraft? {
    let root = try object(from: data)
    guard let value = root["draft"] as? [String: Any],
      let folder = value["folder"] as? [String],
      let title = value["title"] as? String,
      let template = value["template"] as? String
    else { return nil }
    return NewNoteDraft(
      folder: folder,
      title: title,
      template: template,
      tags: value["tags"] as? [String] ?? [],
      pageSize: value["pageSize"] as? String,
      orientation: value["orientation"] as? String)
  }

  static func newNoteStartingTemplates(in data: Data?) throws -> [NewNoteStartingTemplate] {
    let root = try object(from: data)
    let values = root["startingTemplates"] as? [[String: Any]] ?? []
    return values.compactMap { value in
      guard let name = value["name"] as? String,
        let folder = value["folder"] as? [String],
        let paper = value["paper"] as? String,
        let pageSize = value["pageSize"] as? String
      else { return nil }
      return NewNoteStartingTemplate(
        name: name,
        folder: folder,
        paper: paper,
        pageSize: pageSize,
        orientation: value["orientation"] as? String,
        tags: value["tags"] as? [String] ?? [])
    }
  }

  static func settingNewNoteDraft(
    in data: Data?,
    draft: NewNoteDraft?
  ) throws -> Data {
    var root = try object(from: data)
    guard let draft else {
      root.removeValue(forKey: "draft")
      return try encoded(root)
    }
    registerTags(draft.tags, in: &root)
    var value: [String: Any] = [
      "folder": draft.folder,
      "title": draft.title,
      "template": draft.template,
      "tags": normalizedTags(draft.tags),
    ]
    if let pageSize = draft.pageSize { value["pageSize"] = pageSize }
    if let orientation = draft.orientation { value["orientation"] = orientation }
    root["draft"] = value
    return try encoded(root)
  }

  static func settingNewNoteStartingTemplate(
    in data: Data?,
    template: NewNoteStartingTemplate
  ) throws -> Data {
    var root = try object(from: data)
    registerTags(template.tags, in: &root)
    var templates = root["startingTemplates"] as? [[String: Any]] ?? []
    templates.removeAll { $0["name"] as? String == template.name }
    var value: [String: Any] = [
      "name": template.name,
      "folder": template.folder,
      "paper": template.paper,
      "pageSize": template.pageSize,
      "tags": normalizedTags(template.tags),
    ]
    if let orientation = template.orientation { value["orientation"] = orientation }
    templates.append(value)
    root["startingTemplates"] = templates
    return try encoded(root)
  }

  static func completingNewNoteCreation(
    in data: Data?,
    path: [String],
    tags: [String]
  ) throws -> Data {
    var root = try object(from: data)
    registerTags(tags, in: &root)
    var notes = root["notes"] as? [String: Any] ?? [:]
    notes[path.joined(separator: "/")] = [
      "favorite": false,
      "tags": normalizedTags(tags),
      "description": "",
    ]
    root["notes"] = notes
    root.removeValue(forKey: "draft")
    return try encoded(root)
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
  case externalChanges([String])
  case conflictChanged
  case invalidConflictAction(String)
  case invalidRecovery(String)
  case multipleRecoveries(String)

  var errorDescription: String? {
    switch self {
    case .cannotAccessRoot:
      return "Math Notes no longer has access to the selected notes folder."
    case let .coordinationFailed(path):
      return "File coordination did not provide access to \(path)."
    case let .invalidName(message):
      return message
    case let .entryExists(name):
      return "“\(name)” already exists here."
    case let .missingTemplate(name):
      return "Template \(name) has no pages/0001.svg."
    case let .externalChanges(paths):
      return "External changes in \(paths.joined(separator: ", ")). Compare the conflict copies before saving."
    case .conflictChanged:
      return "A version changed during comparison. Reopen the conflict before choosing."
    case let .invalidConflictAction(message):
      return message
    case let .invalidRecovery(message):
      return "Pending edit recovery is invalid: \(message)"
    case let .multipleRecoveries(name):
      return "\(name) has pending edits from multiple app sessions. Keep the recovery records before resolving the conflict."
    }
  }
}

private struct NotebookRecoveryChange: Codable {
  enum Kind: String, Codable {
    case write
    case delete
  }

  let path: String
  let kind: Kind
  let data: Data?
  let base: Data?

  init(change: EngineFileChange, base: Data?) {
    path = change.path
    self.base = base
    switch change.kind {
    case let .write(data):
      kind = .write
      self.data = data
    case .delete:
      kind = .delete
      data = nil
    }
  }

  var engineChange: EngineFileChange {
    switch kind {
    case .write:
      EngineFileChange(path: path, kind: .write(data ?? Data()))
    case .delete:
      EngineFileChange(path: path, kind: .delete)
    }
  }
}

private struct NotebookRecoveryRecord: Codable {
  let id: UUID
  let rootPath: String
  let rootBookmark: Data?
  let notebookPath: [String]
  let notebookBookmark: Data?
  let changes: [NotebookRecoveryChange]
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

  func accommodatePresentedSubitemDeletion(
    at url: URL,
    completionHandler: @escaping ((any Error)?) -> Void
  ) {
    completionHandler(nil)
    DispatchQueue.main.async { [weak self] in
      self?.onChange?()
    }
  }

  func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
    onChange?()
  }
}

final class NotesRootAccess {
  private static let bookmarkKey = "notes-root-bookmark"

  let url: URL
  var onChange: (() -> Void)?

  private let presenter: RootFilePresenter
  private let recoveryDirectory: URL
  private var accessing = true
  private var thumbnailCache: [String: (stamp: String, data: Data)] = [:]
  private var notebookBases: [NotebookReference: [String: Data]] = [:]
  private var recoveredChanges: [NotebookReference: [EngineFileChange]] = [:]
  private var recoveryFiles: [NotebookReference: URL] = [:]
  private var pendingDeleteConflicts:
    [NotebookReference: [String: PendingDeleteConflictState]] = [:]

#if DEBUG
  init(testURL: URL, recoveryURL: URL? = nil) {
    url = testURL
    recoveryDirectory = recoveryURL
      ?? testURL.appendingPathComponent(".math-notes-recovery", isDirectory: true)
    presenter = RootFilePresenter(url: testURL)
    accessing = false
    presenter.onChange = { [weak self] in self?.onChange?() }
    NSFileCoordinator.addFilePresenter(presenter)
  }
#endif

  init(selectedURL: URL) throws {
    guard selectedURL.startAccessingSecurityScopedResource() else {
      throw NotebookStorageError.cannotAccessRoot
    }

    url = selectedURL
    recoveryDirectory = Self.defaultRecoveryDirectory()
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
    recoveryDirectory = Self.defaultRecoveryDirectory()
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

  private static func defaultRecoveryDirectory() -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("Math Notes", isDirectory: true)
      .appendingPathComponent("Recovery", isDirectory: true)
  }

  func persistAsSavedRoot() throws {
    try Self.saveBookmark(for: url)
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
        return left.name.localizedCompare(right.name) == .orderedAscending
      }
    }
  }

  func library(
    in parent: FolderReference,
    overview: Bool = false,
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    try coordinatedRead(at: url) { root in
      let fileManager = FileManager.default
      let metadata = try LibraryMetadataFile.read(at: root)
      let favoritePaths = try LibraryMetadataFile.favoritePaths(in: metadata)
      var folders: [LibraryFolderItem] = []
      var notebooks: [LibraryNotebookItem] = []

      func children(of directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])
          .filter { child in
            !child.lastPathComponent.hasPrefix(".") &&
              (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
          }
      }

      func notebookItem(_ child: URL, path: [String]) throws -> LibraryNotebookItem {
        let reference = NotebookReference(path: path)
        return LibraryNotebookItem(
          reference: reference,
          modified: try Self.notebookModification(at: child),
          favorite: favoritePaths.contains(path.joined(separator: "/")),
          conflicts: try combinedConflictCount(reference, at: child),
          details: try LibraryMetadataFile.noteDetails(in: metadata, path: path))
      }

      if overview {
        func visit(_ directory: URL, path: [String]) throws {
          var directNotes: [(URL, [String])] = []
          var nested: [(URL, [String])] = []
          for child in try children(of: directory) {
            let childPath = path + [child.lastPathComponent]
            if fileManager.fileExists(
              atPath: child.appendingPathComponent("notebook.json").path)
            {
              directNotes.append((child, childPath))
            } else {
              nested.append((child, childPath))
            }
          }

          if !path.isEmpty || !directNotes.isEmpty {
            var modified: Date?
            for (note, _) in directNotes {
              let candidate = try Self.notebookModification(at: note)
              if modified == nil || candidate > modified! { modified = candidate }
            }
            folders.append(
              LibraryFolderItem(
                reference: FolderReference(path: path),
                modified: modified,
                noteCount: directNotes.count,
                coverNote: Self.coverNotebookReference(
                  folderPath: path,
                  names: directNotes.map { $0.1.last! }),
                details: try LibraryMetadataFile.folderDetails(in: metadata, path: path)))
          }

          for (child, childPath) in nested {
            try visit(child, path: childPath)
          }
        }
        try visit(root, path: [])
      } else {
        let directory = parent.path.reduce(root) { partial, component in
          partial.appendingPathComponent(component, isDirectory: true)
        }
        for child in try children(of: directory) {
          let path = parent.path + [child.lastPathComponent]
          guard fileManager.fileExists(
            atPath: child.appendingPathComponent("notebook.json").path)
          else { continue }
          notebooks.append(try notebookItem(child, path: path))
        }
      }

      let nameOrder: (String, String) -> Bool = {
        Self.libraryNamePrecedes($0, $1)
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
          let left = $0.modified ?? .distantPast
          let right = $1.modified ?? .distantPast
          return ascending ? left < right : left > right
        }
        notebooks.sort {
          ascending ? $0.modified < $1.modified : $0.modified > $1.modified
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
        overview: true,
        sort: sort,
        direction: direction)
    }

    return try coordinatedRead(at: url) { root in
      let fileManager = FileManager.default
      let metadata = try LibraryMetadataFile.read(at: root)
      let favoritePaths = try LibraryMetadataFile.favoritePaths(in: metadata)
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
            let details = try LibraryMetadataFile.noteDetails(in: metadata, path: childPath)
            if Self.matchesSearch(
              needle,
              name: name,
              description: details.description,
              tags: details.tags)
            {
              notebooks.append(
                LibraryNotebookItem(
                  reference: NotebookReference(path: childPath),
                  modified: try Self.notebookModification(at: child),
                  favorite: favoritePaths.contains(childPath.joined(separator: "/")),
                  conflicts: try combinedConflictCount(
                    NotebookReference(path: childPath),
                    at: child),
                  details: details))
            }
          } else {
            let details = try LibraryMetadataFile.folderDetails(in: metadata, path: childPath)
            let directNoteNames = try Self.directNotebookNames(in: child)
            if Self.matchesSearch(
              needle,
              name: FolderReference(path: childPath).name,
              description: details.description,
              tags: details.tags,
              additionalNames: directNoteNames)
            {
              folders.append(
                LibraryFolderItem(
                  reference: FolderReference(path: childPath),
                  modified: try Self.latestDirectNotebookModification(in: child),
                  noteCount: directNoteNames.count,
                  coverNote: Self.coverNotebookReference(
                    folderPath: childPath,
                    names: directNoteNames),
                  details: details))
            }
            try visit(child, path: childPath)
          }
        }
      }

      let rootNoteNames = try Self.directNotebookNames(in: root)
      if !rootNoteNames.isEmpty {
        let rootDetails = try LibraryMetadataFile.folderDetails(in: metadata, path: [])
        if Self.matchesSearch(
          needle,
          name: FolderReference(path: []).name,
          description: rootDetails.description,
          tags: rootDetails.tags,
          additionalNames: rootNoteNames)
        {
          folders.append(
            LibraryFolderItem(
              reference: FolderReference(path: []),
              modified: try Self.latestDirectNotebookModification(in: root),
              noteCount: rootNoteNames.count,
              coverNote: Self.coverNotebookReference(folderPath: [], names: rootNoteNames),
              details: rootDetails))
        }
      }

      try visit(root, path: [])
      let nameOrder: (String, String) -> Bool = {
        Self.libraryNamePrecedes($0, $1)
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
          let left = $0.modified ?? .distantPast
          let right = $1.modified ?? .distantPast
          return ascending ? left < right : left > right
        }
        notebooks.sort {
          ascending ? $0.modified < $1.modified : $0.modified > $1.modified
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
              favorite: favoritePaths.contains(childPath.joined(separator: "/")),
              conflicts: try combinedConflictCount(
                NotebookReference(path: childPath),
                at: child),
              details: try LibraryMetadataFile.noteDetails(
                in: LibraryMetadataFile.read(at: root), path: childPath)))
          } else {
            try visit(child, path: childPath)
          }
        }
      }

      try visit(root, path: [])
      let nameOrder: (String, String) -> Bool = {
        Self.libraryNamePrecedes($0, $1)
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
          ascending ? $0.modified < $1.modified : $0.modified > $1.modified
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
      if needle.isEmpty || Self.matchesSearch(
        needle,
        name: item.reference.name,
        description: details.description,
        tags: details.tags)
      {
        notebooks.append(item)
      }
    }

    var folderItems: [LibraryFolderItem] = []
    for reference in try folders() {
      let directory = urlForPath(reference.path)
      let directNoteNames = try coordinatedRead(at: directory) {
        try Self.directNotebookNames(in: $0)
      }
      if reference.path.isEmpty && directNoteNames.isEmpty { continue }

      let details = try folderDetails(for: reference)
      guard details.tags.contains(tag) else { continue }
      guard needle.isEmpty || Self.matchesSearch(
        needle,
        name: reference.name,
        description: details.description,
        tags: details.tags,
        additionalNames: directNoteNames)
      else { continue }

      folderItems.append(
        LibraryFolderItem(
          reference: reference,
          modified: try coordinatedRead(at: directory) {
            try Self.latestDirectNotebookModification(in: $0)
          },
          noteCount: directNoteNames.count,
          coverNote: Self.coverNotebookReference(
            folderPath: reference.path,
            names: directNoteNames),
          details: details))
    }

    let nameOrder: (String, String) -> Bool = {
      Self.libraryNamePrecedes($0, $1)
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
        let left = $0.modified ?? .distantPast
        let right = $1.modified ?? .distantPast
        return ascending ? left < right : left > right
      }
    }
    return LibraryListing(folders: folderItems, notebooks: notebooks)
  }

  func trashNotes(
    query: String = "",
    sort: LibrarySort,
    direction: LibrarySortDirection
  ) throws -> LibraryListing {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return try coordinatedRead(at: url) { root in
      let trash = root.appendingPathComponent(".trash", isDirectory: true)
      guard FileManager.default.fileExists(atPath: trash.path) else {
        return LibraryListing(folders: [], notebooks: [])
      }

      let fileManager = FileManager.default
      let metadata = try LibraryMetadataFile.read(at: root)
      let favoritePaths = try LibraryMetadataFile.favoritePaths(in: metadata)
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
            let details = try LibraryMetadataFile.noteDetails(in: metadata, path: childPath)
            if needle.isEmpty || Self.matchesSearch(
              needle,
              name: child.lastPathComponent,
              description: details.description,
              tags: details.tags)
            {
              notebooks.append(
                LibraryNotebookItem(
                  reference: NotebookReference(path: childPath),
                  modified: try Self.notebookModification(at: child),
                  favorite: favoritePaths.contains(childPath.joined(separator: "/")),
                  conflicts: try combinedConflictCount(
                    NotebookReference(path: childPath),
                    at: child),
                  details: details))
            }
          } else {
            try visit(child, path: childPath)
          }
        }
      }

      try visit(trash, path: [".trash"])
      let nameOrder: (String, String) -> Bool = {
        Self.libraryNamePrecedes($0, $1)
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
          ascending ? $0.modified < $1.modified : $0.modified > $1.modified
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

  func newNoteDraft() throws -> NewNoteDraft? {
    try coordinatedRead(at: url) { root in
      try LibraryMetadataFile.newNoteDraft(in: LibraryMetadataFile.read(at: root))
    }
  }

  func newNoteStartingTemplates() throws -> [NewNoteStartingTemplate] {
    try coordinatedRead(at: url) { root in
      try LibraryMetadataFile.newNoteStartingTemplates(
        in: LibraryMetadataFile.read(at: root))
    }
  }

  func saveNewNoteDraft(_ draft: NewNoteDraft) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let updated = try LibraryMetadataFile.settingNewNoteDraft(
        in: LibraryMetadataFile.read(at: root),
        draft: draft)
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
    }
  }

  func saveNewNoteStartingTemplate(_ template: NewNoteStartingTemplate) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let updated = try LibraryMetadataFile.settingNewNoteStartingTemplate(
        in: LibraryMetadataFile.read(at: root),
        template: template)
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
    }
  }

  func completeNewNoteCreation(
    _ reference: NotebookReference,
    tags: [String]
  ) throws {
    try coordinatedWrite(at: url, options: .forMerging) { root in
      let updated = try LibraryMetadataFile.completingNewNoteCreation(
        in: LibraryMetadataFile.read(at: root),
        path: reference.path,
        tags: tags)
      try updated.write(
        to: root.appendingPathComponent(LibraryMetadataFile.name),
        options: .atomic)
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

  func createFolder(
    parent: FolderReference,
    name: String,
    details: LibraryFolderDetails
  ) throws -> FolderReference {
    let reference = try createFolder(parent: parent, name: name)
    let folderURL = urlForPath(reference.path)
    do {
      try saveFolderDetails(details, for: reference)
      return reference
    } catch {
      try? coordinatedWrite(at: folderURL, options: .forDeleting) { coordinatedURL in
        if FileManager.default.fileExists(atPath: coordinatedURL.path) {
          try FileManager.default.removeItem(at: coordinatedURL)
        }
      }
      throw error
    }
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
    let stamp: String?
    do {
      stamp = try coordinatedRead(at: notebookURL) { coordinatedNotebook in
        try Self.thumbnailStamp(at: coordinatedNotebook)
      }
    } catch {
      guard Self.isMissingFileError(error) else { throw error }
      thumbnailCache.removeValue(forKey: reference.id)
      return nil
    }
    guard let stamp else {
      thumbnailCache.removeValue(forKey: reference.id)
      return nil
    }
    if let cached = thumbnailCache[reference.id], cached.stamp == stamp {
      return cached.data
    }

    do {
      let document = try load(reference)
      let data = try document.pagePNG(index: 0, width: 240)
      thumbnailCache[reference.id] = (stamp: stamp, data: data)
      return data
    } catch {
      guard Self.isMissingFileError(error) else { throw error }
      thumbnailCache.removeValue(forKey: reference.id)
      return nil
    }
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
  func prepareRoot() throws {
    try ensureBuiltinTemplates()
    try ensurePenFile()
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
  func paperPreview(
    template: String,
    pageSize: InkPageSize,
    orientation: InkOrientation,
    width: Int32 = 480
  ) throws -> Data {
    try ensureBuiltinTemplates()
    let pageURL = url
      .appendingPathComponent(".templates", isDirectory: true)
      .appendingPathComponent(template, isDirectory: true)
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("0001.svg")
    guard try itemExists(at: [".templates", template, "pages", "0001.svg"]) else {
      throw NotebookStorageError.missingTemplate(template)
    }
    let page = try coordinatedRead(at: pageURL) { try Data(contentsOf: $0) }
    let document = try EngineDocument.createFromTemplate(
      seed: 1,
      name: template,
      page: page,
      pageSize: pageSize,
      orientation: orientation)
    return try document.pagePNG(index: 0, width: width)
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
    let name = try validatedLibraryName(title)

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

  private func recoveryRootBookmark() -> Data? {
    guard accessing else { return nil }
    return try? url.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
  }

  private func recoveryRootMatches(_ record: NotebookRecoveryRecord) -> Bool {
    let current = url.standardizedFileURL.path
    guard let bookmark = record.rootBookmark else {
      return record.rootPath == current
    }
    var stale = false
    guard let resolved = try? URL(
      resolvingBookmarkData: bookmark,
      bookmarkDataIsStale: &stale)
    else { return false }
    return resolved.standardizedFileURL.path == current
  }

  private func recoveryNotebookMatches(
    _ record: NotebookRecoveryRecord,
    reference: NotebookReference
  ) -> Bool {
    guard let bookmark = record.notebookBookmark else {
      return record.notebookPath == reference.path
    }
    var stale = false
    guard let resolved = try? URL(
      resolvingBookmarkData: bookmark,
      bookmarkDataIsStale: &stale)
    else { return false }
    return resolved.standardizedFileURL.path == urlForNotebook(reference).standardizedFileURL.path
  }

  private func recoveryRecord(
    for reference: NotebookReference
  ) throws -> (file: URL, record: NotebookRecoveryRecord)? {
    if let known = recoveryFiles[reference],
      FileManager.default.fileExists(atPath: known.path)
    {
      do {
        let record = try JSONDecoder().decode(
          NotebookRecoveryRecord.self, from: Data(contentsOf: known))
        guard recoveryRootMatches(record), recoveryNotebookMatches(record, reference: reference) else {
          recoveryFiles.removeValue(forKey: reference)
          return nil
        }
        return (known, record)
      } catch {
        throw NotebookStorageError.invalidRecovery(error.localizedDescription)
      }
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: recoveryDirectory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return nil }

    var matches: [(URL, NotebookRecoveryRecord)] = []
    for file in try FileManager.default.contentsOfDirectory(
      at: recoveryDirectory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles])
      where file.pathExtension == "json"
    {
      let record: NotebookRecoveryRecord
      do {
        record = try JSONDecoder().decode(
          NotebookRecoveryRecord.self, from: Data(contentsOf: file))
      } catch {
        throw NotebookStorageError.invalidRecovery(error.localizedDescription)
      }
      if recoveryRootMatches(record), recoveryNotebookMatches(record, reference: reference) {
        matches.append((file, record))
      }
    }

    guard matches.count <= 1 else {
      throw NotebookStorageError.multipleRecoveries(reference.name)
    }
    guard let match = matches.first else { return nil }
    recoveryFiles[reference] = match.0
    return (match.0, match.1)
  }

  private static func mergedRecoveryChanges(
    _ older: [EngineFileChange],
    _ newer: [EngineFileChange]
  ) -> [EngineFileChange] {
    var byPath = Dictionary(uniqueKeysWithValues: older.map { ($0.path, $0) })
    for change in newer { byPath[change.path] = change }
    return orderedNotebookChanges(Array(byPath.values))
  }

  @MainActor
  func checkpointRecovery(
    _ document: EngineDocument,
    notebook reference: NotebookReference
  ) throws {
    let changes = Self.mergedRecoveryChanges(
      recoveredChanges[reference] ?? [],
      try document.dirtyFiles())
    guard !changes.isEmpty else { return }
    try writeRecovery(changes, notebook: reference, base: notebookBases[reference] ?? [:])
    try document.markSaved()
  }

  private func recoveryNotebookBookmark(_ reference: NotebookReference) -> Data? {
    try? urlForNotebook(reference).bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
  }

  private func writeRecovery(
    _ changes: [EngineFileChange],
    notebook reference: NotebookReference,
    base: [String: Data]
  ) throws {
    try FileManager.default.createDirectory(
      at: recoveryDirectory,
      withIntermediateDirectories: true)
    let existing = try recoveryRecord(for: reference)
    let record = NotebookRecoveryRecord(
      id: existing?.record.id ?? UUID(),
      rootPath: url.standardizedFileURL.path,
      rootBookmark: existing?.record.rootBookmark ?? recoveryRootBookmark(),
      notebookPath: reference.path,
      notebookBookmark: existing?.record.notebookBookmark ?? recoveryNotebookBookmark(reference),
      changes: changes.map {
        NotebookRecoveryChange(change: $0, base: base[$0.path])
      })
    let file = existing?.file
      ?? recoveryDirectory.appendingPathComponent(record.id.uuidString).appendingPathExtension("json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(record).write(to: file, options: .atomic)
    recoveryFiles[reference] = file
    recoveredChanges[reference] = changes
  }

  private func clearRecovery(_ reference: NotebookReference) throws {
    let file = recoveryFiles[reference] ?? (try recoveryRecord(for: reference)?.file)
    if let file, FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
    recoveryFiles.removeValue(forKey: reference)
    recoveredChanges.removeValue(forKey: reference)
  }

  func hasRecoveredChanges(_ reference: NotebookReference) -> Bool {
    !(recoveredChanges[reference]?.isEmpty ?? true)
  }

  @MainActor
  func load(_ reference: NotebookReference) throws -> EngineDocument {
    let notebookURL = urlForNotebook(reference)
    let recovery = try recoveryRecord(for: reference)
    let recoveredNotebookJSON = recovery?.record.changes.first {
      $0.path == "notebook.json" && $0.kind == .write
    }?.data
    let snapshot = try coordinatedRead(at: notebookURL) { coordinatedURL in
      try Self.readSnapshot(
        at: coordinatedURL,
        recoveredNotebookJSON: recoveredNotebookJSON)
    }

    var restored = snapshot.base
    if let recovery {
      for change in recovery.record.changes {
        switch change.engineChange.kind {
        case let .write(data): restored[change.path] = data
        case .delete: restored.removeValue(forKey: change.path)
        }
      }
    }
    guard let notebookJSON = restored["notebook.json"] else {
      throw NotebookStorageError.invalidRecovery("The recovered notebook has no notebook.json.")
    }
    let index = try JSONDecoder().decode(NotebookIndex.self, from: notebookJSON)

    let document = EngineDocument(seed: UInt64.random(in: 1...UInt64.max))
    try document.loadNotebook(notebookJSON)
    for (path, data) in restored.sorted(by: { $0.key < $1.key })
      where path.hasPrefix("pages/") && path.hasSuffix(".svg")
    {
      try document.loadPage(path: path, data: data)
    }
    for (path, data) in restored.sorted(by: { $0.key < $1.key })
      where path.hasPrefix("assets/")
    {
      try document.loadAsset(path: path, data: data)
    }

    if let template = index.template {
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

    var base = snapshot.base
    if let recovery {
      for change in recovery.record.changes {
        if let saved = change.base {
          base[change.path] = saved
        } else {
          base.removeValue(forKey: change.path)
        }
      }
      recoveredChanges[reference] = recovery.record.changes.map(\.engineChange)
      recoveryFiles[reference] = recovery.file
    } else {
      recoveredChanges.removeValue(forKey: reference)
      recoveryFiles.removeValue(forKey: reference)
    }
    notebookBases[reference] = base
    return document
  }

  private static func namedConflicts(at notebookURL: URL, listedPages: [String]) throws -> [NotebookConflictCandidate] {
    notebookConflictCandidates(
      listedPages: listedPages,
      rootFiles: try fileNames(in: notebookURL),
      pageFiles: try fileNames(in: notebookURL.appendingPathComponent("pages", isDirectory: true)),
      assetFiles: try fileNames(in: notebookURL.appendingPathComponent("assets", isDirectory: true)))
  }

  private static func fileVersions(at target: URL) -> [NSFileVersion] {
    NSFileVersion.unresolvedConflictVersionsOfItem(at: target) ?? []
  }

  private static func unresolvedFileVersions(at notebookURL: URL, listedPages: [String]) -> [(path: String, version: NSFileVersion)] {
    (["notebook.json"] + listedPages).flatMap { path in
      fileVersions(at: fileURL(in: notebookURL, path: path)).map {
        (path: path, version: $0)
      }
    }
  }

  private static func conflictCount(
    at notebookURL: URL,
    recoveredNotebookJSON: Data? = nil
  ) throws -> Int {
    let indexURL = notebookURL.appendingPathComponent("notebook.json")
    let data: Data
    if FileManager.default.fileExists(atPath: indexURL.path) {
      data = try Data(contentsOf: indexURL)
    } else if let recoveredNotebookJSON {
      data = recoveredNotebookJSON
    } else {
      data = try Data(contentsOf: indexURL)
    }
    let index = try JSONDecoder().decode(NotebookIndex.self, from: data)
    let pages = (index.pages ?? []).map(\.file)
    let named = try namedConflicts(at: notebookURL, listedPages: pages).count
    return named + unresolvedFileVersions(at: notebookURL, listedPages: pages).count
  }

  private func pendingDeleteConflictCount(
    _ reference: NotebookReference,
    at notebookURL: URL
  ) throws -> Int {
    let pending = pendingDeleteConflicts[reference] ?? [:]
    return try pending.keys.reduce(into: 0) { count, path in
      if try Self.currentFile(in: notebookURL, path: path) != nil {
        count += 1
      }
    }
  }

  private func combinedConflictCount(
    _ reference: NotebookReference,
    at notebookURL: URL
  ) throws -> Int {
    let stored = try Self.conflictCount(at: notebookURL)
    let pending = try pendingDeleteConflictCount(reference, at: notebookURL)
    return stored + pending
  }

  func conflictCount(_ reference: NotebookReference) throws -> Int {
    let notebookURL = urlForNotebook(reference)
    let recovery = try recoveryRecord(for: reference)
    let recoveredNotebookJSON = recovery?.record.changes.first {
      $0.path == "notebook.json" && $0.kind == .write
    }?.data
    return try coordinatedRead(at: notebookURL) { coordinatedNotebook in
      let stored = try Self.conflictCount(
        at: coordinatedNotebook,
        recoveredNotebookJSON: recoveredNotebookJSON)
      let pending = try pendingDeleteConflictCount(reference, at: coordinatedNotebook)
      return stored + pending
    }
  }

  @MainActor
  func conflicts(_ reference: NotebookReference) throws -> [NotebookConflict] {
    let notebookURL = urlForNotebook(reference)
    return try coordinatedRead(at: notebookURL) { coordinatedNotebook in
      let snapshot = try Self.readSnapshot(at: coordinatedNotebook)
      let index = try JSONDecoder().decode(NotebookIndex.self, from: snapshot.notebookJSON)
      let listedPages = (index.pages ?? []).map(\.file)
      var result: [NotebookConflict] = []

      for candidate in try Self.namedConflicts(
        at: coordinatedNotebook,
        listedPages: listedPages)
      {
        guard let copyBytes = try Self.currentFile(
          in: coordinatedNotebook,
          path: candidate.copy)
        else { continue }
        let originalBytes = try Self.currentFile(
          in: coordinatedNotebook,
          path: candidate.original)
        result.append(
          Self.makeConflict(
            id: "named:\(candidate.copy)",
            original: candidate.original,
            provider: candidate.provider,
            originalBytes: originalBytes,
            copyBytes: copyBytes,
            source: .namedCopy(path: candidate.copy),
            snapshot: snapshot,
            listedPages: listedPages))
      }

      for item in Self.unresolvedFileVersions(
        at: coordinatedNotebook,
        listedPages: listedPages)
      {
        let copyBytes = try Data(contentsOf: item.version.url)
        let originalBytes = try Self.currentFile(
          in: coordinatedNotebook,
          path: item.path)
        result.append(
          Self.makeConflict(
            id: "version:\(item.path):\(String(describing: item.version.persistentIdentifier))",
            original: item.path,
            provider: "iCloud Drive",
            originalBytes: originalBytes,
            copyBytes: copyBytes,
            source: .fileVersion(item.version),
            snapshot: snapshot,
            listedPages: listedPages))
      }

      var livePending: [String: PendingDeleteConflictState] = [:]
      for (path, state) in (pendingDeleteConflicts[reference] ?? [:])
        .sorted(by: { $0.key < $1.key })
      {
        guard let originalBytes = try Self.currentFile(
          in: coordinatedNotebook,
          path: path)
        else { continue }
        livePending[path] = state
        result.append(
          Self.makeConflict(
            id: "local-delete:\(path)",
            original: path,
            provider: "Math Notes",
            originalBytes: originalBytes,
            copyBytes: nil,
            source: .localDelete,
            snapshot: snapshot,
            listedPages: listedPages))
      }
      if livePending.isEmpty {
        pendingDeleteConflicts.removeValue(forKey: reference)
      } else {
        pendingDeleteConflicts[reference] = livePending
      }

      return result.sorted { $0.id < $1.id }
    }
  }

  @MainActor
  func resolveConflict(
    _ reference: NotebookReference,
    conflict: NotebookConflict,
    choice: NotebookConflictChoice
  ) throws {
    let notebookURL = urlForNotebook(reference)
    try coordinatedWrite(at: notebookURL, options: .forMerging) { coordinatedNotebook in
      let currentOriginal = try Self.currentFile(
        in: coordinatedNotebook,
        path: conflict.original)
      guard currentOriginal == conflict.originalBytes else {
        throw NotebookStorageError.conflictChanged
      }

      let currentCopy: Data?
      switch conflict.source {
      case let .namedCopy(path):
        currentCopy = try Self.currentFile(in: coordinatedNotebook, path: path)
      case let .fileVersion(version):
        currentCopy = try Data(contentsOf: version.url)
      case .localDelete:
        currentCopy = nil
      }
      guard currentCopy == conflict.copyBytes else {
        throw NotebookStorageError.conflictChanged
      }

      let snapshot = try Self.readSnapshot(at: coordinatedNotebook)
      let index = try JSONDecoder().decode(NotebookIndex.self, from: snapshot.notebookJSON)
      let listedPages = (index.pages ?? []).map(\.file)
      var changes: [EngineFileChange] = []

      switch choice {
      case .original:
        switch conflict.source {
        case .localDelete:
          if conflict.page && !listedPages.contains(conflict.original) {
            guard let state = pendingDeleteConflicts[reference]?[conflict.original] else {
              throw NotebookStorageError.conflictChanged
            }
            let document = try Self.conflictDocument(
              snapshot: snapshot,
              replacing: nil,
              with: nil)
            let index = min(state.pageIndex ?? listedPages.count, listedPages.count)
            try document.listUnlistedPage(
              path: conflict.original,
              fallbackID: state.pageID,
              at: index)
            changes = try document.dirtyFiles().filter {
              $0.path != conflict.original
            }
          }
        case .namedCopy, .fileVersion:
          if conflict.originalBytes == nil {
            guard conflict.page,
              let pageIndex = listedPages.firstIndex(of: conflict.original)
            else {
              throw NotebookStorageError.invalidConflictAction(
                "Only a missing page can keep an external deletion.")
            }
            let document = try Self.conflictDocument(
              snapshot: snapshot,
              replacing: nil,
              with: nil)
            try document.deletePage(at: pageIndex)
            changes = try document.dirtyFiles()
          }
        }

      case .copy:
        if case .localDelete = conflict.source {
          if conflict.page,
            let pageIndex = listedPages.firstIndex(of: conflict.original)
          {
            let document = try Self.conflictDocument(
              snapshot: snapshot,
              replacing: nil,
              with: nil)
            try document.deletePage(at: pageIndex)
            changes = try document.dirtyFiles()
          } else {
            changes = [
              EngineFileChange(
                path: conflict.original,
                kind: .delete),
            ]
          }
        } else {
          guard let copyBytes = conflict.copyBytes else {
            throw NotebookStorageError.conflictChanged
          }
          if conflict.notebook || conflict.page {
            _ = try Self.conflictDocument(
              snapshot: snapshot,
              replacing: conflict.original,
              with: copyBytes)
          }
          changes = [
            EngineFileChange(
              path: conflict.original,
              kind: .write(copyBytes)),
          ]
        }

      case .both:
        if case .localDelete = conflict.source {
          throw NotebookStorageError.invalidConflictAction(
            "A local deletion can only keep the file or keep the deletion.")
        }
        guard conflict.originalBytes != nil else {
          throw NotebookStorageError.invalidConflictAction(
            "Restore the conflict copy or keep the deletion.")
        }
        guard let copyBytes = conflict.copyBytes,
          conflict.page,
          let pageIndex = listedPages.firstIndex(of: conflict.original)
        else {
          throw NotebookStorageError.invalidConflictAction(
            "Keep both is available only for page conflicts.")
        }
        let document = try Self.conflictDocument(
          snapshot: snapshot,
          replacing: nil,
          with: nil)
        try document.importPageSVG(at: pageIndex + 1, data: copyBytes)
        changes = try document.dirtyFiles()
      }

      try Self.writeChangesDirect(changes, notebookURL: coordinatedNotebook)

      switch conflict.source {
      case let .namedCopy(path):
        let target = Self.fileURL(in: coordinatedNotebook, path: path)
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
      case let .fileVersion(version):
        version.isResolved = true
        try version.remove()
      case .localDelete:
        pendingDeleteConflicts[reference]?.removeValue(forKey: conflict.original)
        if pendingDeleteConflicts[reference]?.isEmpty == true {
          pendingDeleteConflicts.removeValue(forKey: reference)
        }
      }
    }

    notebookBases.removeValue(forKey: reference)
  }

  @MainActor
  func save(_ document: EngineDocument, notebook reference: NotebookReference) throws {
    let changes = Self.mergedRecoveryChanges(
      recoveredChanges[reference] ?? [],
      try document.dirtyFiles())
    guard !changes.isEmpty else { return }

    let notebookURL = urlForNotebook(reference)
    let base = notebookBases[reference] ?? [:]
    try writeRecovery(changes, notebook: reference, base: base)
    var safe: [EngineFileChange] = []
    var conflicts: [EngineFileChange] = []
    var nextPending = pendingDeleteConflicts[reference] ?? [:]

    for change in changes {
      try ensureParentDirectory(
        for: change.path,
        notebookURL: notebookURL)
    }

    try coordinatedWrite(at: notebookURL, options: .forMerging) { coordinatedNotebook in
      for change in changes {
        let current = try Self.currentFile(in: coordinatedNotebook, path: change.path)
        let target: Data?
        switch change.kind {
        case let .write(data): target = data
        case .delete: target = nil
        }
        if notebookFileHasExternalChange(
          current: current,
          base: base[change.path],
          target: target)
        {
          conflicts.append(change)
          if case .delete = change.kind,
            nextPending[change.path] == nil
          {
            var pageIndex: Int?
            var pageID: String?
            if let notebookJSON = base["notebook.json"],
              let index = try? JSONDecoder().decode(NotebookIndex.self, from: notebookJSON),
              let found = (index.pages ?? []).firstIndex(where: { $0.file == change.path })
            {
              pageIndex = found
              pageID = index.pages?[found].id
            }
            nextPending[change.path] = PendingDeleteConflictState(
              pageIndex: pageIndex,
              pageID: pageID)
          }
        } else {
          safe.append(change)
          if case .delete = change.kind {
            nextPending.removeValue(forKey: change.path)
          }
        }
      }

      try Self.writeChangesDirect(safe, notebookURL: coordinatedNotebook)

      for change in conflicts {
        guard case let .write(data) = change.kind else { continue }
        let copyPath = Self.conflictCopyPath(for: change.path)
        let target = Self.fileURL(in: coordinatedNotebook, path: copyPath)
        try data.write(to: target, options: .atomic)
      }
    }

    if nextPending.isEmpty {
      pendingDeleteConflicts.removeValue(forKey: reference)
    } else {
      pendingDeleteConflicts[reference] = nextPending
    }

    var nextBase = base
    for change in safe {
      switch change.kind {
      case let .write(data): nextBase[change.path] = data
      case .delete: nextBase.removeValue(forKey: change.path)
      }
    }
    notebookBases[reference] = nextBase

    let localChangesAreDurable = conflicts.isEmpty || conflicts.allSatisfy {
      if case .write = $0.kind { return true }
      return false
    }
    if localChangesAreDurable {
      try clearRecovery(reference)
      try document.markSaved()
    }
    guard conflicts.isEmpty else {
      throw NotebookStorageError.externalChanges(conflicts.map { $0.path })
    }
  }

  private static func fileURL(in notebookURL: URL, path: String) -> URL {
    var result = notebookURL
    for component in path.split(separator: "/") {
      result.appendPathComponent(String(component))
    }
    return result
  }

  private static func currentFile(in notebookURL: URL, path: String) throws -> Data? {
    let target = fileURL(in: notebookURL, path: path)
    guard FileManager.default.fileExists(atPath: target.path) else { return nil }
    return try Data(contentsOf: target)
  }

  private static func conflictCopyPath(for path: String) -> String {
    let ext = (path as NSString).pathExtension
    let stem = ext.isEmpty ? path : String(path.dropLast(ext.count + 1))
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
    let suffix = " (math-notes conflict " + stamp + " " + UUID().uuidString + ")"
    return ext.isEmpty ? stem + suffix : stem + suffix + "." + ext
  }

  private static func writeChangesDirect(
    _ changes: [EngineFileChange],
    notebookURL: URL
  ) throws {
    for change in orderedNotebookChanges(changes) {
      let target = Self.fileURL(in: notebookURL, path: change.path)
      switch change.kind {
      case let .write(data):
        try data.write(to: target, options: .atomic)
      case .delete:
        guard FileManager.default.fileExists(atPath: target.path) else { continue }
        try FileManager.default.removeItem(at: target)
      }
    }
  }

  @MainActor
  private static func makeConflict(
    id: String,
    original: String,
    provider: String,
    originalBytes: Data?,
    copyBytes: Data?,
    source: NotebookConflictSource,
    snapshot: Snapshot,
    listedPages: [String]
  ) -> NotebookConflict {
    let left = conflictPreview(
      original: original,
      bytes: originalBytes,
      snapshot: snapshot,
      listedPages: listedPages,
      missingSummary: "This file was deleted outside Math Notes.")
    let right = conflictPreview(
      original: original,
      bytes: copyBytes,
      snapshot: snapshot,
      listedPages: listedPages,
      missingSummary: "This file is deleted in Math Notes.")
    return NotebookConflict(
      id: id,
      original: original,
      provider: provider,
      originalBytes: originalBytes,
      copyBytes: copyBytes,
      left: left.image,
      right: right.image,
      leftSummary: left.summary,
      rightSummary: right.summary,
      notebook: original == "notebook.json",
      page: original.hasPrefix("pages/") && original.hasSuffix(".svg"),
      source: source)
  }

  @MainActor
  private static func conflictPreview(
    original: String,
    bytes: Data?,
    snapshot: Snapshot,
    listedPages: [String],
    missingSummary: String
  ) -> (image: Data?, summary: String) {
    guard let bytes else {
      return (nil, missingSummary)
    }
    do {
      if original == "notebook.json" {
        let value = try JSONDecoder().decode(NotebookIndex.self, from: bytes)
        let pages = (value.pages ?? []).map(\.file).joined(separator: "\n")
        let layers = (value.layers ?? []).map { layer in
          layer.name
            + (layer.hidden ? " (hidden)" : "")
            + (layer.locked ? " (locked)" : "")
        }.joined(separator: "\n")
        return (nil, "Pages\n\(pages)\n\nLayers\n\(layers)")
      }

      if original.hasPrefix("pages/") && original.hasSuffix(".svg") {
        let document = try conflictDocument(
          snapshot: snapshot,
          replacing: original,
          with: bytes)
        let pageIndex: Int
        if let listedIndex = listedPages.firstIndex(of: original) {
          pageIndex = listedIndex
        } else {
          pageIndex = listedPages.count
          try document.listUnlistedPage(
            path: original,
            fallbackID: nil,
            at: pageIndex)
        }
        return (try document.pagePNG(index: pageIndex, width: 1000), original)
      }

      let ext = (original as NSString).pathExtension.lowercased()
      if ["png", "jpg", "jpeg"].contains(ext) {
        return (bytes, original)
      }
      return (nil, String(decoding: bytes, as: UTF8.self))
    } catch {
      return (nil, error.localizedDescription)
    }
  }

  @MainActor
  private static func conflictDocument(
    snapshot: Snapshot,
    replacing path: String?,
    with replacement: Data?
  ) throws -> EngineDocument {
    let document = EngineDocument(seed: UInt64.random(in: 1...UInt64.max))
    let notebook = path == "notebook.json" ? replacement ?? snapshot.notebookJSON : snapshot.notebookJSON
    try document.loadNotebook(notebook)

    var loadedReplacement = false
    for file in snapshot.pages {
      let data: Data
      if file.path == path, let replacement {
        data = replacement
        loadedReplacement = true
      } else {
        data = file.data
      }
      try document.loadPage(
        path: file.path,
        data: data,
        allowParseError: file.path != path)
    }
    if let path, path.hasPrefix("pages/"), !loadedReplacement, let replacement {
      try document.loadPage(
        path: path,
        data: replacement,
        allowParseError: false)
    }

    loadedReplacement = false
    for file in snapshot.assets {
      let data: Data
      if file.path == path, let replacement {
        data = replacement
        loadedReplacement = true
      } else {
        data = file.data
      }
      try document.loadAsset(path: file.path, data: data)
    }
    if let path, path.hasPrefix("assets/"), !loadedReplacement, let replacement {
      try document.loadAsset(path: path, data: replacement)
    }
    try document.markSaved()
    return document
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

    var base: [String: Data] {
      var result = ["notebook.json": notebookJSON]
      for file in pages + assets { result[file.path] = file.data }
      return result
    }
  }

  private struct NotebookIndex: Decodable {
    struct Page: Decodable {
      let id: String?
      let file: String
    }

    struct Layer: Decodable {
      let id: String
      let name: String
      let hidden: Bool
      let locked: Bool
    }

    let template: String?
    let pages: [Page]?
    let layers: [Layer]?
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
    guard let indexData = try dataIfPresent(at: indexURL) else { return nil }
    let index = try JSONDecoder().decode(NotebookIndex.self, from: indexData)
    guard let firstPage = index.pages?.first?.file else { return nil }

    let pageURL = firstPage.split(separator: "/").reduce(notebookURL) { partial, component in
      partial.appendingPathComponent(String(component))
    }
    guard let pageData = try dataIfPresent(at: pageURL) else { return nil }
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

  private static func dataIfPresent(at url: URL) throws -> Data? {
    do {
      return try Data(contentsOf: url)
    } catch {
      guard isMissingFileError(error) else { throw error }
      return nil
    }
  }

  private static func isMissingFileError(_ error: Error) -> Bool {
    let cocoa = error as NSError
    return cocoa.domain == NSCocoaErrorDomain
      && (cocoa.code == CocoaError.Code.fileNoSuchFile.rawValue
        || cocoa.code == CocoaError.Code.fileReadNoSuchFile.rawValue)
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

  private static func libraryNamePrecedes(_ left: String, _ right: String) -> Bool {
    left.lowercased().compare(right.lowercased(), options: .literal) == .orderedAscending
  }

  private static func matchesSearch(
    _ needle: String,
    name: String,
    description: String,
    tags: [String],
    additionalNames: [String] = []
  ) -> Bool {
    let lower = needle.lowercased()
    return name.lowercased().contains(lower) ||
      description.lowercased().contains(lower) ||
      tags.contains(where: { $0.lowercased().contains(lower) }) ||
      additionalNames.contains(where: { $0.lowercased().contains(lower) })
  }

  private static func coverNotebookReference(
    folderPath: [String],
    names: [String]
  ) -> NotebookReference? {
    guard let name = names.min(by: libraryNamePrecedes) else { return nil }
    return NotebookReference(path: folderPath + [name])
  }

  private static func directNotebookNames(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])
      .filter { child in
        guard !child.lastPathComponent.hasPrefix(".") else { return false }
        return FileManager.default.fileExists(
          atPath: child.appendingPathComponent("notebook.json").path)
      }
      .map(\.lastPathComponent)
  }

  private static func latestDirectNotebookModification(in directory: URL) throws -> Date? {
    var latest: Date?
    for child in try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])
    {
      guard !child.lastPathComponent.hasPrefix("."),
        FileManager.default.fileExists(
          atPath: child.appendingPathComponent("notebook.json").path)
      else { continue }
      let candidate = try notebookModification(at: child)
      if latest == nil || candidate > latest! { latest = candidate }
    }
    return latest
  }

  private static func directNotebookCount(in directory: URL) throws -> Int {
    try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles])
      .filter { child in
        guard !child.lastPathComponent.hasPrefix(".") else { return false }
        return FileManager.default.fileExists(
          atPath: child.appendingPathComponent("notebook.json").path)
      }
      .count
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

  private static func readSnapshot(
    at notebookURL: URL,
    recoveredNotebookJSON: Data? = nil
  ) throws -> Snapshot {
    let indexURL = notebookURL.appendingPathComponent("notebook.json")
    let notebookJSON: Data
    if FileManager.default.fileExists(atPath: indexURL.path) {
      notebookJSON = try Data(contentsOf: indexURL)
    } else if let recoveredNotebookJSON {
      notebookJSON = recoveredNotebookJSON
    } else {
      notebookJSON = try Data(contentsOf: indexURL)
    }
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

  private static func fileNames(in directory: URL) throws -> [String] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
      .filter { candidate in
        (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      }
      .map(\.lastPathComponent)
      .sorted()
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
