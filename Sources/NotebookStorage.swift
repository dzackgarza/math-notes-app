import Foundation

struct NotebookReference: Hashable, Identifiable {
  let path: [String]

  var id: String { path.joined(separator: "/") }
  var name: String { path.last ?? "Untitled" }
}

enum NotebookStorageError: LocalizedError {
  case cannotAccessRoot
  case coordinationFailed(String)

  var errorDescription: String? {
    switch self {
    case .cannotAccessRoot:
      return "Math Notes no longer has access to the selected notes folder."
    case let .coordinationFailed(path):
      return "File coordination did not provide access to \(path)."
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

  private static func saveBookmark(for url: URL) throws {
    let data = try url.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    UserDefaults.standard.set(data, forKey: bookmarkKey)
  }

  private func urlForNotebook(_ reference: NotebookReference) -> URL {
    reference.path.reduce(url) {
      $0.appendingPathComponent($1, isDirectory: true)
    }
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
    let template: String?
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
