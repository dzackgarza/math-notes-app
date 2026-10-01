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

struct LibraryFolderItem: Identifiable {
  let reference: FolderReference
  let modified: Date?

  var id: String { reference.id }
}

struct LibraryNotebookItem: Identifiable {
  let reference: NotebookReference
  let modified: Date

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

  func library(in parent: FolderReference, sort: LibrarySort) throws -> LibraryListing {
    try coordinatedRead(at: url) { root in
      let directory = parent.path.reduce(root) { partial, component in
        partial.appendingPathComponent(component, isDirectory: true)
      }
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
              modified: try Self.notebookModification(at: child)))
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
      switch sort {
      case .name:
        folders.sort { nameOrder($0.reference.name, $1.reference.name) }
        notebooks.sort { nameOrder($0.reference.name, $1.reference.name) }
      case .modified:
        folders.sort {
          switch ($0.modified, $1.modified) {
          case let (left?, right?) where left != right:
            return left > right
          default:
            return nameOrder($0.reference.name, $1.reference.name)
          }
        }
        notebooks.sort {
          if $0.modified != $1.modified { return $0.modified > $1.modified }
          return nameOrder($0.reference.name, $1.reference.name)
        }
      }
      return LibraryListing(folders: folders, notebooks: notebooks)
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
