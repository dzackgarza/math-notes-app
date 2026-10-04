import CoreGraphics
import Foundation
import Observation

enum EditorSplitAxis: String, CaseIterable, Equatable {
  case horizontal
  case vertical

  mutating func rotate() {
    self = self == .horizontal ? .vertical : .horizontal
  }
}

struct EditorLinkedViewport: Equatable {
  var relativeScale: CGFloat
  var center: CGPoint
}

enum NotebookSaveStatus: Equatable {
  case saved
  case pending
  case saving
  case failed

  var label: String {
    switch self {
    case .saved: "Saved"
    case .pending: "Unsaved changes"
    case .saving: "Saving…"
    case .failed: "Save failed"
    }
  }
}

@MainActor
@Observable
final class OpenNotebookViewState: Identifiable {
  let id: UUID
  var activeLayerID: String?
  var bookmarkMode = false
  var currentPage: Int
  var pageNavigationRevision = 0
  var fitRevision = 0
  var editorPageCommand: EditorPageCommand?
  var captureActive = false

  init(
    id: UUID = UUID(),
    currentPage: Int = 0
  ) {
    self.id = id
    self.currentPage = currentPage
  }
}

@MainActor
@Observable
final class OpenNotebookSession: Identifiable {
  let id: UUID
  let reference: NotebookReference
  let document: EngineDocument
  let primaryView: OpenNotebookViewState
  var documentRevision = 0
  var conflictCount: Int
  var saveStatus = NotebookSaveStatus.saved

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
    self.primaryView = OpenNotebookViewState()
  }

  func markUnsaved() {
    saveStatus = .pending
  }

  func performSave(_ operation: () throws -> Void) throws {
    saveStatus = .saving
    do {
      try operation()
      saveStatus = .saved
    } catch {
      saveStatus = .failed
      throw error
    }
  }

  var activeLayerID: String? {
    get { primaryView.activeLayerID }
    set { primaryView.activeLayerID = newValue }
  }

  var bookmarkMode: Bool {
    get { primaryView.bookmarkMode }
    set { primaryView.bookmarkMode = newValue }
  }

  var currentPage: Int {
    get { primaryView.currentPage }
    set { primaryView.currentPage = newValue }
  }

  var pageNavigationRevision: Int {
    get { primaryView.pageNavigationRevision }
    set { primaryView.pageNavigationRevision = newValue }
  }

  var fitRevision: Int {
    get { primaryView.fitRevision }
    set { primaryView.fitRevision = newValue }
  }

  var editorPageCommand: EditorPageCommand? {
    get { primaryView.editorPageCommand }
    set { primaryView.editorPageCommand = newValue }
  }

  var captureActive: Bool {
    get { primaryView.captureActive }
    set { primaryView.captureActive = newValue }
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
  private(set) var secondaryReference: NotebookReference?
  private(set) var secondaryView: OpenNotebookViewState?
  private(set) var rightFocused = false
  private(set) var linkedViews = false
  private(set) var linkedViewport: EditorLinkedViewport?
  private(set) var splitAxis: EditorSplitAxis = .horizontal

  var selected: OpenNotebookSession? {
    guard opened.indices.contains(tab) else { return nil }
    return opened[tab]
  }

  var active: OpenNotebookSession? {
    inLibrary ? nil : selected
  }

  var secondary: OpenNotebookSession? {
    guard let secondaryReference else { return nil }
    return find(secondaryReference)
  }

  var splitOpen: Bool {
    secondary != nil && secondaryView != nil
  }

  var focusedSession: OpenNotebookSession? {
    guard !inLibrary else { return nil }
    if rightFocused, let secondary {
      return secondary
    }
    return active
  }

  var focusedView: OpenNotebookViewState? {
    guard !inLibrary else { return nil }
    if rightFocused, let secondaryView {
      return secondaryView
    }
    return active?.primaryView
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
    guard !captureActive(for: target) else {
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
    guard !targets.contains(where: { captureActive(for: $0) }) else {
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
    guard !captureActive(for: opened[index]) else {
      throw OpenNotesStateError.captureInProgress("reloading this note")
    }
    let replacement = try load(reference)
    opened[index] = replacement
    if secondaryReference == reference {
      let currentPage = secondaryView?.currentPage ?? replacement.primaryView.currentPage
      secondaryView = OpenNotebookViewState(currentPage: currentPage)
      linkedViewport = nil
    }
    return replacement
  }

  func toggleSplit() throws {
    try requireNoCapture("splitting notes")
    if splitOpen {
      closeSplit()
      return
    }
    guard let selected else { return }
    secondaryReference = selected.reference
    secondaryView = OpenNotebookViewState(
      currentPage: selected.primaryView.currentPage)
    rightFocused = false
    linkedViewport = nil
  }

  @discardableResult
  func showReference(
    _ reference: NotebookReference,
    save: (OpenNotebookSession) throws -> Void,
    load: (NotebookReference) throws -> OpenNotebookSession
  ) throws -> OpenNotebookSession {
    guard splitOpen else {
      throw OpenNotesStateError.captureInProgress("changing a closed reference view")
    }
    let previousID = selected?.id
    let note = try open(reference, save: save, load: load)
    secondaryReference = note.reference
    secondaryView = OpenNotebookViewState(
      currentPage: note.primaryView.currentPage)
    if let previousID,
      let previous = opened.firstIndex(where: { $0.id == previousID })
    {
      tab = previous
    }
    rightFocused = true
    linkedViewport = nil
    return note
  }

  func focusRight(_ right: Bool) {
    guard splitOpen || !right else { return }
    rightFocused = right
  }

  func closeSplitIfAllowed() throws {
    try requireNoCapture("closing split view")
    closeSplit()
  }

  func closeSplit() {
    secondaryReference = nil
    secondaryView = nil
    rightFocused = false
    linkedViewport = nil
  }

  func toggleLinkedViews() {
    guard splitOpen else { return }
    linkedViews.toggle()
    if !linkedViews {
      linkedViewport = nil
    }
  }

  func rotateSplit() {
    guard splitOpen else { return }
    splitAxis.rotate()
  }

  func setLinkedViewport(_ viewport: EditorLinkedViewport) {
    guard splitOpen, linkedViews, linkedViewport != viewport else { return }
    linkedViewport = viewport
  }

  func reset() {
    opened.removeAll()
    tab = 0
    inLibrary = true
    closeSplit()
    linkedViews = false
    splitAxis = .horizontal
  }

  func requireNoCapture(_ action: String) throws {
    guard !opened.contains(where: { captureActive(for: $0) }) else {
      throw OpenNotesStateError.captureInProgress(action)
    }
  }

  private func captureActive(for session: OpenNotebookSession) -> Bool {
    if session.primaryView.captureActive {
      return true
    }
    return secondaryReference == session.reference
      && secondaryView?.captureActive == true
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
    if let secondary, ids.contains(secondary.id) {
      closeSplit()
    }

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
