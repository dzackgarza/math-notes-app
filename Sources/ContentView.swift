import Foundation
import InkEngine
import SwiftUI

@MainActor
private struct NotebookSession {
  let reference: NotebookReference
  let document: EngineDocument
}

@MainActor
struct ContentView: View {
  @State private var root: NotesRootAccess?
  @State private var libraryFolder = FolderReference(path: [])
  @State private var libraryListing = LibraryListing(folders: [], notebooks: [])
  @State private var librarySort: LibrarySort = .name
  @State private var libraryGrid = true
  @AppStorage("pageArrangement") private var pageArrangementRaw = EditorPageArrangement.vertical.rawValue
  @State private var session: NotebookSession?
  @State private var showingFolderPicker = false
  @State private var restoredRoot = false
  @State private var errorMessage: String?
  @State private var selectedTool: EditorTool = .pen
  @State private var penLibrary = EditorPenLibrary.defaults
  @State private var currentPage = 0
  @State private var documentRevision = 0
  @State private var pageNavigationRevision = 0
  @State private var sharePayload: SharePayload?
  @State private var pdfExport: PDFExportRequest?
  @State private var showingPDFImporter = false
  @State private var pdfImportProgress: String?
  @State private var showingNewNote = false
  @State private var newNoteFolders: [FolderReference] = []
  @State private var newNoteTemplates: [String] = []
  @State private var libraryMutation: LibraryMutationRequest?
  @State private var pagePaper: PagePaperRequest?
  @State private var showingPageOverview = false

  var body: some View {
    NavigationStack {
      Group {
        if let session {
          InkEditorView(
            document: session.document,
            arrangement: EditorPageArrangement.stored(pageArrangementRaw),
            penLibrary: $penLibrary,
            tool: $selectedTool,
            currentPage: $currentPage,
            documentRevision: $documentRevision,
            pageNavigationRevision: $pageNavigationRevision,
            onEditCommitted: saveOpenNotebook,
            onPensChanged: persistPenLibrary,
            onError: { errorMessage = $0.localizedDescription })
            .navigationTitle(session.reference.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .topBarLeading) {
                Button {
                  self.session = nil
                  refreshLibrary()
                } label: {
                  Label("Library", systemImage: "chevron.left")
                }
              }
              ToolbarItem(placement: .topBarTrailing) {
                pagesMenu(session)
              }
              ToolbarItem(placement: .topBarTrailing) {
                viewMenu
              }
              ToolbarItem(placement: .topBarTrailing) {
                documentMenu(session)
              }
            }
        } else if let root {
          libraryView(root: root)
        } else {
          ContentUnavailableView {
            Label("Choose Notes Folder", systemImage: "folder")
          } description: {
            Text("Math Notes edits notebooks directly in a folder you choose in Files.")
          } actions: {
            Button("Choose Folder") {
              showingFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
    }
    .sheet(isPresented: $showingFolderPicker) {
      NotesFolderPicker(
        onPick: { url in
          showingFolderPicker = false
          selectRoot(url)
        },
        onCancel: {
          showingFolderPicker = false
        })
    }
    .sheet(item: $sharePayload) { payload in
      ActivityShareSheet(url: payload.url)
    }
    .sheet(item: $pdfExport) { request in
      PDFExportSheet(
        request: request,
        onExport: { firstPage, pageCount in
          guard let session else {
            pdfExport = nil
            return
          }
          sharePDF(session, firstPage: firstPage, pageCount: pageCount)
        },
        onCancel: { pdfExport = nil })
    }
    .sheet(isPresented: $showingPDFImporter) {
      PDFImportPicker(
        onPick: { url in
          showingPDFImporter = false
          Task {
            await importPDF(url)
          }
        },
        onCancel: { showingPDFImporter = false })
    }
    .sheet(isPresented: $showingNewNote) {
      NewNoteSheet(
        folders: newNoteFolders,
        templates: newNoteTemplates,
        initialParent: libraryFolder,
        onCreate: createNewNote,
        onCancel: { showingNewNote = false })
    }
    .sheet(item: $libraryMutation) { request in
      LibraryMutationSheet(
        request: request,
        onApply: { name, parent in
          applyLibraryMutation(request, name: name, parent: parent)
        },
        onCancel: { libraryMutation = nil })
    }
    .sheet(item: $pagePaper) { request in
      PagePaperSheet(
        request: request,
        onTemplate: applyPageTemplate,
        onPageSize: applyPageSize,
        onDone: { pagePaper = nil })
    }
    .sheet(isPresented: $showingPageOverview) {
      if let session {
        PageOverviewSheet(
          document: session.document,
          currentPage: $currentPage,
          onSelect: selectOverviewPage,
          onEdit: pageOverviewEdited,
          onError: { errorMessage = $0.localizedDescription },
          onDone: { showingPageOverview = false })
      }
    }
    .alert(
      "Math Notes",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { presented in
          if !presented { errorMessage = nil }
        })
    ) {
      Button("OK", role: .cancel) {
        errorMessage = nil
      }
    } message: {
      Text(errorMessage ?? "")
    }
    .task {
      restoreSavedRoot()
    }
    .overlay {
      if let pdfImportProgress {
        ZStack {
          Color.black.opacity(0.2)
            .ignoresSafeArea()
          VStack(spacing: 12) {
            ProgressView()
            Text(pdfImportProgress)
              .font(.headline)
          }
          .padding(24)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
      }
    }
  }

  @ViewBuilder
  private func documentMenu(_ session: NotebookSession) -> some View {
    Menu {
      Button("Save", systemImage: "square.and.arrow.down") {
        saveOpenNotebook()
      }
      Button("Export PDF…", systemImage: "square.and.arrow.up") {
        preparePDFExport(session)
      }
      Divider()
      Button("Close note", systemImage: "xmark") {
        self.session = nil
        refreshLibrary()
      }
    } label: {
      Label("More", systemImage: "ellipsis")
    }
  }

  @ViewBuilder
  private var viewMenu: some View {
    let selected = EditorPageArrangement.stored(pageArrangementRaw)
    Menu {
      ForEach(EditorPageArrangement.allCases) { arrangement in
        Button {
          pageArrangementRaw = arrangement.rawValue
        } label: {
          if arrangement == selected {
            Label(arrangement.label, systemImage: "checkmark")
          } else {
            Label(arrangement.label, systemImage: arrangement.systemImage)
          }
        }
      }
    } label: {
      Label("View", systemImage: "eye")
    }
  }
  @ViewBuilder
  private func pagesMenu(_ session: NotebookSession) -> some View {
    let count = (try? session.document.pageCount()) ?? 0
    Menu {
      Button("Page Overview", systemImage: "square.grid.2x2") {
        showingPageOverview = true
      }
      Divider()
      Button("Add page", systemImage: "plus.rectangle") {
        editPages(session) { document in
          try document.appendPage()
        }
      }
      Button("Insert page before", systemImage: "rectangle.badge.plus") {
        editPages(session) { document in
          try document.insertPage(at: currentPage)
        }
      }
      Button("Insert page after", systemImage: "rectangle.badge.plus") {
        editPages(session) { document in
          try document.insertPage(at: currentPage + 1)
        }
      }
      Button("Duplicate page", systemImage: "plus.square.on.square") {
        editPages(session) { document in
          try document.duplicatePage(at: currentPage)
        }
      }
      Button("Paper for New Pages", systemImage: "doc.text") {
        preparePagePaper(session)
      }
      Divider()
      Button("Delete page", systemImage: "trash", role: .destructive) {
        editPages(session) { document in
          try document.deletePage(at: currentPage)
          currentPage = min(currentPage, max(0, try document.pageCount() - 1))
        }
      }
      .disabled(count <= 1)
    } label: {
      Label("Pages", systemImage: "doc.on.doc")
    }
  }

  @ViewBuilder
  private func libraryView(root: NotesRootAccess) -> some View {
    NativeLibraryView(
      root: root,
      folder: libraryFolder,
      listing: libraryListing,
      sort: librarySort,
      grid: libraryGrid,
      openFolder: { folder in
        libraryFolder = folder
        refreshLibrary()
      },
      openNotebook: openNotebook,
      goUp: {
        guard !libraryFolder.path.isEmpty else { return }
        libraryFolder = FolderReference(path: Array(libraryFolder.path.dropLast()))
        refreshLibrary()
      },
      setSort: { sort in
        librarySort = sort
        refreshLibrary()
      },
      toggleLayout: { libraryGrid.toggle() },
      createNote: prepareNewNote,
      importPDF: { showingPDFImporter = true },
      createFolder: { prepareLibraryMutation(.createFolder) },
      renameEntry: { prepareLibraryMutation(.rename($0)) },
      moveEntry: { prepareLibraryMutation(.move($0)) },
      trashEntry: moveLibraryEntryToTrash,
      refresh: refreshLibrary,
      chooseRoot: { showingFolderPicker = true })
  }

  private func restoreSavedRoot() {
    guard !restoredRoot else { return }
    restoredRoot = true
    guard let restored = NotesRootAccess.restore() else { return }
    installRoot(restored)
  }

  private func selectRoot(_ url: URL) {
    do {
      installRoot(try NotesRootAccess(selectedURL: url))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func installRoot(_ newRoot: NotesRootAccess) {
    session = nil
    libraryFolder = FolderReference(path: [])
    libraryListing = LibraryListing(folders: [], notebooks: [])
    root = newRoot
    reloadPenLibrary()
    newRoot.onChange = {
      Task { @MainActor in
        refreshLibrary()
        reloadPenLibrary()
      }
    }
    refreshLibrary()
  }


  private func reloadPenLibrary() {
    guard let root else {
      penLibrary = .defaults
      return
    }
    do {
      penLibrary = try root.penLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
  private func persistPenLibrary(_ library: EditorPenLibrary) {
    penLibrary = library
    guard let root else { return }
    do {
      try root.savePenLibrary(library)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refreshLibrary() {
    guard let root else {
      libraryListing = LibraryListing(folders: [], notebooks: [])
      return
    }

    do {
      libraryListing = try root.library(in: libraryFolder, sort: librarySort)
    } catch {
      if !libraryFolder.path.isEmpty {
        libraryFolder = FolderReference(path: [])
        do {
          libraryListing = try root.library(in: libraryFolder, sort: librarySort)
          return
        } catch {
          errorMessage = error.localizedDescription
          return
        }
      }
      errorMessage = error.localizedDescription
    }
  }

  private func prepareLibraryMutation(_ mode: LibraryMutationMode) {
    guard let root else { return }
    do {
      let allFolders = try root.folders()
      let initialParent: FolderReference
      let folders: [FolderReference]

      switch mode {
      case .createFolder:
        initialParent = libraryFolder
        folders = allFolders
      case let .rename(entry):
        initialParent = FolderReference(path: Array(entry.path.dropLast()))
        folders = allFolders
      case let .move(entry):
        initialParent = FolderReference(path: Array(entry.path.dropLast()))
        if entry.kind == .folder {
          folders = allFolders.filter { candidate in
            !(candidate.path.count >= entry.path.count &&
              Array(candidate.path.prefix(entry.path.count)) == entry.path)
          }
        } else {
          folders = allFolders
        }
      }

      libraryMutation = LibraryMutationRequest(
        mode: mode,
        folders: folders,
        initialParent: initialParent)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func applyLibraryMutation(
    _ request: LibraryMutationRequest,
    name: String,
    parent: FolderReference
  ) {
    guard let root else { return }
    do {
      switch request.mode {
      case .createFolder:
        _ = try root.createFolder(parent: parent, name: name)
      case let .rename(entry):
        let currentParent = FolderReference(path: Array(entry.path.dropLast()))
        _ = try root.moveEntry(
          path: entry.path,
          toParent: currentParent,
          name: name)
      case let .move(entry):
        _ = try root.moveEntry(
          path: entry.path,
          toParent: parent,
          name: entry.name)
      }
      libraryMutation = nil
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func moveLibraryEntryToTrash(_ entry: LibraryEntryTarget) {
    guard let root else { return }
    do {
      _ = try root.moveToTrash(path: entry.path)
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func prepareNewNote() {
    guard let root else { return }
    do {
      newNoteFolders = try root.folders()
      newNoteTemplates = try root.templateNames()
      guard !newNoteTemplates.isEmpty else {
        throw NotebookStorageError.missingTemplate("blank")
      }
      showingNewNote = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func importPDF(_ url: URL) async {
    guard let root else { return }
    var importedReference: NotebookReference?
    var completed = 0

    do {
      let pdf = try PDFImportDocument(url: url)
      let title = url.deletingPathExtension().lastPathComponent
      pdfImportProgress = "Importing PDF: 0 / \(pdf.pageCount) pages"
      await Task.yield()

      let firstPage = try pdf.rasterizedPage(at: 0)
      let (reference, document) = try root.createNote(
        title: title,
        parent: libraryFolder,
        template: "blank",
        pageSize: INK_PAGE_A4,
        orientation: INK_PORTRAIT)
      importedReference = reference
      try document.importPageImage(
        at: 0,
        png: firstPage.png,
        widthPt: firstPage.widthPt,
        heightPt: firstPage.heightPt)
      try document.deletePage(at: 1)
      try root.save(document, notebook: reference)
      completed = 1
      pdfImportProgress = "Importing PDF: 1 / \(pdf.pageCount) pages"
      await Task.yield()

      for index in 1..<pdf.pageCount {
        let page = try pdf.rasterizedPage(at: index)
        try document.importPageImage(
          at: index,
          png: page.png,
          widthPt: page.widthPt,
          heightPt: page.heightPt)
        try root.save(document, notebook: reference)
        completed = index + 1
        pdfImportProgress = "Importing PDF: \(completed) / \(pdf.pageCount) pages"
        await Task.yield()
      }

      selectedTool = .pen
      currentPage = 0
      documentRevision = 0
      pageNavigationRevision = 0
      session = NotebookSession(reference: reference, document: document)
      pdfImportProgress = nil
      refreshLibrary()
    } catch {
      pdfImportProgress = nil
      refreshLibrary()
      if let importedReference {
        let noun = completed == 1 ? "page" : "pages"
        errorMessage =
          "\(error.localizedDescription) \(completed) imported \(noun) remain in \(importedReference.name)."
      } else {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func createNewNote(_ request: NewNoteRequest) {
    guard let root else { return }
    do {
      let (reference, document) = try root.createNote(
        title: request.title,
        parent: request.parent,
        template: request.template,
        pageSize: request.pageSize,
        orientation: request.orientation)
      showingNewNote = false
      selectedTool = .pen
      currentPage = 0
      documentRevision = 0
      pageNavigationRevision = 0
      session = NotebookSession(reference: reference, document: document)
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openNotebook(_ reference: NotebookReference) {
    guard let root else { return }
    do {
      currentPage = 0
      documentRevision = 0
      pageNavigationRevision = 0
      session = NotebookSession(
        reference: reference,
        document: try root.load(reference))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func preparePDFExport(_ session: NotebookSession) {
    do {
      pdfExport = PDFExportRequest(
        pageCount: try session.document.pageCount(),
        currentPage: currentPage)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func sharePDF(
    _ session: NotebookSession,
    firstPage: Int,
    pageCount: Int
  ) {
    do {
      try saveOpenNotebookThrowing()
      let total = try session.document.pageCount()
      let data = try session.document.exportPDF(
        title: session.reference.name,
        firstPage: firstPage,
        pageCount: pageCount)
      let safeName = session.reference.name.replacingOccurrences(of: "/", with: "-")
      let baseName = firstPage == 0 && pageCount == total ? safeName : "\(safeName)-pages-\(firstPage + 1)-\(firstPage + pageCount)"
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(baseName)
        .appendingPathExtension("pdf")
      try data.write(to: url, options: .atomic)
      let payload = SharePayload(url: url)
      pdfExport = nil
      DispatchQueue.main.async {
        sharePayload = payload
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func preparePagePaper(_ session: NotebookSession) {
    guard let root else { return }
    do {
      pagePaper = PagePaperRequest(
        templates: try root.templateNames(),
        template: try root.templateName(for: session.reference),
        pageSize: try session.document.pageSize())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func applyPageTemplate(_ name: String) {
    guard let root, let session else { return }
    do {
      try root.applyTemplate(name: name, to: session.document)
      try root.save(session.document, notebook: session.reference)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func applyPageSize(
    _ size: InkPageSize,
    _ orientation: InkOrientation,
    _ width: Double,
    _ height: Double
  ) {
    guard let root, let session else { return }
    do {
      try session.document.setPageSize(
        size,
        orientation: orientation,
        width: width,
        height: height)
      try root.save(session.document, notebook: session.reference)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func selectOverviewPage(_ index: Int) {
    currentPage = index
    pageNavigationRevision &+= 1
    showingPageOverview = false
  }
  private func pageOverviewEdited(_ page: Int) {
    currentPage = page
    documentRevision &+= 1
    pageNavigationRevision &+= 1
    saveOpenNotebook()
  }
  private func editPages(
    _ session: NotebookSession,
    _ action: (EngineDocument) throws -> Void
  ) {
    do {
      try action(session.document)
      documentRevision &+= 1
      saveOpenNotebook()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func saveOpenNotebookThrowing() throws {
    guard let root, let session else { return }
    try root.save(session.document, notebook: session.reference)
  }

  private func saveOpenNotebook() {
    do {
      try saveOpenNotebookThrowing()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
