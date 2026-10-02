import Foundation
import Observation

@MainActor
@Observable
final class OpenNotebookSession: Identifiable {
  let id: UUID
  let reference: NotebookReference
  let document: EngineDocument
  var activeLayerID: String?
  var bookmarkMode = false
  var currentPage = 0
  var documentRevision = 0
  var pageNavigationRevision = 0
  var fitRevision = 0
  var editorPageCommand: EditorPageCommand?
  var captureActive = false
  var conflictCount: Int

  init(
    id: UUID = UUID(),
    reference: NotebookReference,
    document: EngineDocument,
    conflictCount: Int = 0
  ) {
    self.id = id
    self.reference = reference
    self.document = document
    self.conflictCount = conflictCount
  }
}

enum OpenNotesStateError: LocalizedError {
  case captureInProgress(String)
  case saveFailed(reference: NotebookReference, underlying: Error)

  var errorDescription: String? {
    switch self {
    case let .captureInProgress(action):
      "Finish the current figure before \(action)."
    case let .saveFailed(_, underlying):
      underlying.localizedDescription
    }
  }
}

@MainActor
@Observable
final class OpenNotesState {
  private(set) var opened: [OpenNotebookSession] = []
  private(set) var tab = 0
  private(set) var inLibrary = true

  var selected: OpenNotebookSession? {
    guard opened.indices.contains(tab) else { return nil }
    return opened[tab]
  }

  var active: OpenNotebookSession? {
    inLibrary ? nil : selected
  }

  func find(_ reference: NotebookReference) -> OpenNotebookSession? {
    opened.first { $0.reference == reference }
  }

  func show(_ session: OpenNotebookSession) {
    if let index = opened.firstIndex(where: { $0.reference == session.reference }) {
      tab = index
    } else {
      opened.append(session)
      tab = opened.count - 1
    }
    inLibrary = false
  }

  @discardableResult
  func open(
    _ reference: NotebookReference,
    save: (OpenNotebookSession) throws -> Void,
    load: (NotebookReference) throws -> OpenNotebookSession
  ) throws -> OpenNotebookSession {
    try requireNoCapture("switching notes")
    if let active {
      try saveOne(active, save: save)
    }

    if let existing = find(reference),
      let index = opened.firstIndex(where: { $0.id == existing.id })
    {
      tab = index
      inLibrary = false
      return existing
    }

    let session = try load(reference)
    show(session)
    return session
  }

  func showLibrary(
    save: (OpenNotebookSession) throws -> Void
  ) throws {
    try requireNoCapture("opening the library")
    inLibrary = true
    try saveAll(save: save)
  }

  func saveAll(
    save: (OpenNotebookSession) throws -> Void
  ) throws {
    var firstFailure: OpenNotesStateError?
    for session in opened {
      do {
        try save(session)
      } catch {
        if firstFailure == nil {
          firstFailure = .saveFailed(
            reference: session.reference,
            underlying: error)
        }
      }
    }
    if let firstFailure {
      throw firstFailure
    }
  }

  func close(
    _ index: Int,
    save: (OpenNotebookSession) throws -> Void
  ) throws {
    guard opened.indices.contains(index) else { return }
    let target = opened[index]
    guard !target.captureActive else {
      throw OpenNotesStateError.captureInProgress("closing this note")
    }
    try saveOne(target, save: save)
    release([target.id])
  }

  func closeAll(
    save: (OpenNotebookSession) throws -> Void
  ) throws {
    try requireNoCapture("changing notes folders")
    try saveAll(save: save)
    release(Set(opened.map(\.id)))
  }

  func closeUnder(
    _ path: [String],
    save: (OpenNotebookSession) throws -> Void
  ) throws {
    let targets = opened.filter { session in
      session.reference.path.count >= path.count
        && Array(session.reference.path.prefix(path.count)) == path
    }
    guard !targets.isEmpty else { return }
    guard !targets.contains(where: { $0.captureActive }) else {
      throw OpenNotesStateError.captureInProgress("moving this note")
    }

    var firstFailure: OpenNotesStateError?
    for session in targets {
      do {
        try save(session)
      } catch {
        if firstFailure == nil {
          firstFailure = .saveFailed(
            reference: session.reference,
            underlying: error)
        }
      }
    }
    if let firstFailure {
      throw firstFailure
    }
    release(Set(targets.map(\.id)))
  }

  @discardableResult
  func reloadIfOpen(
    _ reference: NotebookReference,
    load: (NotebookReference) throws -> OpenNotebookSession
  ) throws -> OpenNotebookSession? {
    guard let index = opened.firstIndex(where: { $0.reference == reference }) else {
      return nil
    }
    guard !opened[index].captureActive else {
      throw OpenNotesStateError.captureInProgress("reloading this note")
    }
    let replacement = try load(reference)
    opened[index] = replacement
    return replacement
  }

  func reset() {
    opened.removeAll()
    tab = 0
    inLibrary = true
  }

  func requireNoCapture(_ action: String) throws {
    guard !opened.contains(where: { $0.captureActive }) else {
      throw OpenNotesStateError.captureInProgress(action)
    }
  }

  private func saveOne(
    _ session: OpenNotebookSession,
    save: (OpenNotebookSession) throws -> Void
  ) throws {
    do {
      try save(session)
    } catch {
      throw OpenNotesStateError.saveFailed(
        reference: session.reference,
        underlying: error)
    }
  }

  private func release(_ ids: Set<UUID>) {
    guard !ids.isEmpty else { return }
    let previousIndex = tab
    let selectedID = selected?.id
    opened.removeAll { ids.contains($0.id) }

    guard !opened.isEmpty else {
      tab = 0
      inLibrary = true
      return
    }

    if let selectedID,
      let selectedIndex = opened.firstIndex(where: { $0.id == selectedID })
    {
      tab = selectedIndex
    } else {
      tab = min(previousIndex, opened.count - 1)
    }
  }
}
