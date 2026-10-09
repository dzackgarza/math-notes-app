import Foundation
import InkEngine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum OpenNotePickerPurpose {
  case tab
  case reference
  case linkTarget

  var title: String { "Open note" }
}

private enum BookmarkPickerPurpose {
  case navigate
  case link
}

@MainActor
private struct PendingLink {
  let sourceReference: NotebookReference
  let sourceFile: String
  let viewState: OpenNotebookViewState
  var targetReference: NotebookReference?
}

@MainActor
private struct DeletedPageToast: Identifiable {
  let id = UUID()
  let session: OpenNotebookSession
  let viewState: OpenNotebookViewState
  let number: Int
}

@MainActor
private struct NotebookEditorPane: View {
  @Bindable var session: OpenNotebookSession
  @Bindable var viewState: OpenNotebookViewState
  let active: Bool
  let focused: Bool
  let linked: Bool
  let linkedViewport: EditorLinkedViewport?
  let arrangement: EditorPageArrangement
  let fingerDraws: Bool
  let hiddenTools: Set<String>
  @Binding var penLibrary: EditorPenLibrary
  @Binding var tool: EditorTool
  @Binding var drawingTool: EditorTool
  @Binding var eraserMode: EditorEraserMode
  @Binding var selectorMode: EditorSelectorMode
  @Binding var spaceMode: EditorSpaceMode
  @Binding var previousPencilTool: EditorTool?
  let onFocus: () -> Void
  let onViewportChanged: (EditorLinkedViewport) -> Void
  let onEditCommitted: () -> Void
  let onSaveRequested: () -> Void
  let onPensChanged: (EditorPenLibrary) -> Void
  let onInsertImage: () -> Void
  let clippingsOpen: Bool
  let onShowClippings: () -> Void
  let onSaveClipping: (String) -> Void
  let onLinkSelectionRequested: (Int) -> Void
  let onFollowLink: (String, Int) -> Void
  let onDropClipping: (String, CGPoint) -> Bool
  let onEditFigure: (String) -> Void
  let onError: (Error) -> Void

  var body: some View {
    InkEditorView(
      document: session.document,
      arrangement: arrangement,
      fitRevision: viewState.fitRevision,
      penLibrary: $penLibrary,
      tool: $tool,
      drawingTool: $drawingTool,
      eraserMode: $eraserMode,
      selectorMode: $selectorMode,
      spaceMode: $spaceMode,
      previousPencilTool: $previousPencilTool,
      activeLayerID: $viewState.activeLayerID,
      bookmarkMode: $viewState.bookmarkMode,
      currentPage: $viewState.currentPage,
      documentRevision: $session.documentRevision,
      pageNavigationRevision: $viewState.pageNavigationRevision,
      pageCommand: $viewState.editorPageCommand,
      active: active,
      focused: focused,
      linked: linked,
      linkedViewport: linkedViewport,
      fingerDraws: fingerDraws,
      hiddenTools: hiddenTools,
      onFocus: onFocus,
      onViewportChanged: onViewportChanged,
      onFitStateChanged: { viewState.fitActive = $0 },
      onEditCommitted: onEditCommitted,
      onSaveRequested: onSaveRequested,
      onPensChanged: onPensChanged,
      onInsertImage: onInsertImage,
      clippingsOpen: clippingsOpen,
      onShowClippings: onShowClippings,
      onSaveClipping: onSaveClipping,
      onSelectionChanged: { viewState.selectionActive = $0 },
      onLinkSelectionRequested: onLinkSelectionRequested,
      onFollowLink: onFollowLink,
      onDropClipping: onDropClipping,
      onCaptureChanged: { viewState.captureActive = $0 },
      onEditFigure: onEditFigure,
      onError: onError)
      .id(viewState.id)
  }
}

private struct PendingPDFImport {
  let url: URL
  let scopedAccess: Bool
}

@MainActor
struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var sceneDelegate: MathNotesSceneDelegate
  @State private var root: NotesRootAccess?
  @State private var libraryFolder = FolderReference(path: [])
  @State private var libraryNotebookOpen = false
  @State private var libraryListing = LibraryListing(folders: [], notebooks: [])
  @State private var libraryFolderDetails: LibraryFolderDetails?
  @State private var libraryQuery = ""
  @State private var libraryScope: LibraryScope = .folder
  @State private var libraryTags: [LibraryTag] = []
  @State private var libraryTagCounts: [String: Int] = [:]
  @State private var libraryTag: String?
  @State private var librarySort: LibrarySort = .name
  @State private var librarySortDirection: LibrarySortDirection = .ascending
  @State private var libraryGrid = true
  @AppStorage("pageArrangement") private var pageArrangementRaw = EditorPageArrangement.vertical.rawValue
  @AppStorage("editorSplitFraction") private var editorSplitFraction = 0.5
  @AppStorage("fingerDraws") private var fingerDraws = false
  @AppStorage("showTabStrip") private var showTabStrip = true
  @AppStorage("hiddenTools") private var hiddenToolsRaw = ""
  @State private var openNotes = OpenNotesState()
  @State private var showingFolderPicker = false
  @State private var folderPickerDirectory: URL?
  @State private var restoredRoot = false
  @State private var errorMessage: String?
  @State private var libraryNotice: String?
  @State private var selectedTool: EditorTool = .pen
  @State private var selectedDrawingTool: EditorTool = .pen
  @State private var eraserMode: EditorEraserMode = .stroke
  @State private var selectorMode: EditorSelectorMode = .freehand
  @State private var spaceMode: EditorSpaceMode = .reflow
  @State private var previousPencilTool: EditorTool?
  @State private var penLibrary = EditorPenLibrary.defaults
  @State private var sharePayload: SharePayload?
  @State private var exportPayload: ExportPayload?
  @State private var pdfExport: PDFExportRequest?
  @State private var showingPDFImporter = false
  @State private var showingImageImporter = false
  @State private var pdfImportProgress: String?
  @State private var pendingPDFImport: PendingPDFImport?
  @State private var showingNewNotebook = false
  @State private var newNotebookFolders: [FolderReference] = []
  @State private var newNotebookKnownTags: [LibraryTag] = []
  @State private var newNotebookDefaults = LibraryFolderDetails(
    description: "",
    paper: "dotted",
    coverColor: "#24324A",
    coverStyle: "classic",
    tags: [])
  @State private var showingNewNote = false
  @State private var newNoteFolders: [FolderReference] = []
  @State private var newNoteTemplates: [String] = []
  @State private var newNoteKnownTags: [LibraryTag] = []
  @State private var newNoteFolderDefaults = LibraryFolderDetails(
    description: "",
    paper: "dotted",
    coverColor: "#24324A",
    coverStyle: "classic",
    tags: [])
  @State private var newNoteDraft: NewNoteDraft?
  @State private var newNoteStartingTemplates: [NewNoteStartingTemplate] = []
  @State private var libraryMutation: LibraryMutationRequest?
  @State private var libraryDetails: LibraryDetailsRequest?
  @State private var showingNewTag = false
  @State private var pagePaper: PagePaperRequest?
  @State private var showingPageOverview = false
  @State private var showingLayers = false
  @State private var goToPage: GoToPageRequest?
  @State private var bookmarks: BookmarksRequest?
  @State private var bookmarkPickerPurpose: BookmarkPickerPurpose = .navigate
  @State private var pendingLink: PendingLink?
  @State private var showingLinkChooser = false
  @State private var figureEditor: FigureEditorRequest?
  @State private var conflictReview: ConflictReviewRequest?
  @State private var conflictReviewChanged = false
  @State private var showingOpenNotePicker = false
  @State private var showingEditorSettings = false
  @State private var deletedPageToast: DeletedPageToast?
  @State private var settingsFromLibrary = false
  @State private var chooseFolderAfterSettings = false
  @State private var openNotePickerPurpose: OpenNotePickerPurpose = .tab
  @State private var openNoteChoices: [LibraryNotebookItem] = []

  private var session: OpenNotebookSession? {
    openNotes.focusedSession
  }

  private var viewState: OpenNotebookViewState? {
    openNotes.focusedView
  }

  private var hiddenTools: Set<String> {
    Set(hiddenToolsRaw.split(separator: ",").map(String.init))
  }

  private var followLinksBinding: Binding<Bool> {
    Binding(
      get: { selectedTool == .navigate },
      set: { enabled in
        selectedTool = enabled ? .navigate : selectedDrawingTool
      })
  }

  private var activeLayerID: String? {
    get { viewState?.activeLayerID }
    nonmutating set { viewState?.activeLayerID = newValue }
  }

  private var bookmarkMode: Bool {
    get { viewState?.bookmarkMode ?? false }
    nonmutating set { viewState?.bookmarkMode = newValue }
  }

  private var currentPage: Int {
    get { viewState?.currentPage ?? 0 }
    nonmutating set { viewState?.currentPage = newValue }
  }

  private var documentRevision: Int {
    get { session?.documentRevision ?? 0 }
    nonmutating set { session?.documentRevision = newValue }
  }

  private var pageNavigationRevision: Int {
    get { viewState?.pageNavigationRevision ?? 0 }
    nonmutating set { viewState?.pageNavigationRevision = newValue }
  }

  private var fitRevision: Int {
    get { viewState?.fitRevision ?? 0 }
    nonmutating set { viewState?.fitRevision = newValue }
  }

  private var editorPageCommand: EditorPageCommand? {
    get { viewState?.editorPageCommand }
    nonmutating set { viewState?.editorPageCommand = newValue }
  }

  var body: some View {
    NavigationStack {
      Group {
        if let root {
          ZStack {
            workspaceView
              .opacity(openNotes.inLibrary ? 0 : 1)
              .allowsHitTesting(!openNotes.inLibrary)
              .accessibilityHidden(openNotes.inLibrary)

            if openNotes.inLibrary {
              libraryView(root: root)
                .background(NativeTheme.board)
            }
          }
        } else {
          ContentUnavailableView {
            Label(
              needsRootReconnect ? "Reconnect folder" : "Choose notes folder",
              systemImage: "folder")
          } description: {
            Text(
              needsRootReconnect
                ? "Math Notes needs access to your notes folder again."
                : "Your notes live in a folder on this device.")
          } actions: {
            if needsRootReconnect {
              Button("Reconnect folder") {
                folderPickerDirectory = NotesRootAccess.savedRootURL
                showingFolderPicker = true
              }
              .buttonStyle(.borderedProminent)
            }
            if needsRootReconnect {
              Button("Choose notes folder") {
                folderPickerDirectory = nil
                showingFolderPicker = true
              }
              .buttonStyle(.bordered)
              .disabled(!restoredRoot)
            } else {
              Button("Choose notes folder") {
                folderPickerDirectory = nil
                showingFolderPicker = true
              }
              .buttonStyle(.borderedProminent)
              .disabled(!restoredRoot)
            }
          }
        }
      }
    }
    .sheet(isPresented: $showingFolderPicker) {
      NotesFolderPicker(
        initialDirectory: folderPickerDirectory,
        onPick: { url in
          showingFolderPicker = false
          folderPickerDirectory = nil
          selectRoot(url)
        },
        onCancel: {
          showingFolderPicker = false
          folderPickerDirectory = nil
        })
    }
    .sheet(
      isPresented: $showingEditorSettings,
      onDismiss: {
        if chooseFolderAfterSettings {
          chooseFolderAfterSettings = false
          folderPickerDirectory = nil
          showingFolderPicker = true
        }
      }
    ) {
      if settingsFromLibrary {
        EditorSettingsSheet(
          fingerDraws: $fingerDraws,
          followLinks: nil,
          showTabStrip: $showTabStrip,
          hiddenToolsRaw: $hiddenToolsRaw,
          onChooseFolder: { chooseFolderAfterSettings = true })
      } else {
        EditorSettingsSheet(
          fingerDraws: $fingerDraws,
          followLinks: followLinksBinding,
          showTabStrip: $showTabStrip,
          hiddenToolsRaw: $hiddenToolsRaw,
          onChooseFolder: nil)
      }
    }
    .sheet(isPresented: $showingOpenNotePicker) {
      if let root {
        OpenNotePickerSheet(
          root: root,
          title: openNotePickerPurpose.title,
          notes: openNoteChoices,
          opened: Set(openNotes.opened.map(\.reference)),
          onOpen: { reference in
            showingOpenNotePicker = false
            switch openNotePickerPurpose {
            case .tab:
              openNotebook(reference)
            case .reference:
              showReference(reference)
            case .linkTarget:
              prepareLinkDestinations(reference)
            }
          },
          onCancel: {
            showingOpenNotePicker = false
            if case .linkTarget = openNotePickerPurpose {
              pendingLink = nil
            }
          })
      }
    }
    .sheet(item: $sharePayload) { payload in
      ActivityShareSheet(url: payload.url)
    }
    .sheet(item: $exportPayload) { payload in
      DocumentExportPicker(url: payload.url)
    }
    .sheet(item: $pdfExport) { request in
      PDFExportSheet(
        request: request,
        onExport: { firstPage, pageCount, layerIDs in
          pdfExport = nil
          guard let exportSession = openNotes.opened.first(where: { $0.id == request.sessionID }) else {
            return
          }
          finishPDFExport(
            exportSession,
            destination: request.destination,
            firstPage: firstPage,
            pageCount: pageCount,
            layerIDs: layerIDs)
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
    .fileImporter(
      isPresented: $showingImageImporter,
      allowedContentTypes: [.svg, .png, .jpeg, .heic, .heif, .tiff]
    ) { result in
      switch result {
      case let .success(url):
        importImage(url)
      case let .failure(error):
        errorMessage = error.localizedDescription
      }
    }
    .sheet(isPresented: $showingNewNotebook) {
      NewNotebookSheet(
        folders: newNotebookFolders,
        knownTags: newNotebookKnownTags,
        initialParent: libraryFolder,
        defaults: newNotebookDefaults,
        renderPreview: renderPaperPreview,
        onCreate: createNewNotebook,
        onCancel: { showingNewNotebook = false })
        .presentationSizing(.page.fitted(horizontal: false, vertical: true))
    }
    .sheet(isPresented: $showingNewNote) {
      NewNoteSheet(
        folders: newNoteFolders,
        templates: newNoteTemplates,
        knownTags: newNoteKnownTags,
        initialParent: libraryFolder,
        folderDefaults: newNoteFolderDefaults,
        draft: newNoteDraft,
        startingTemplates: newNoteStartingTemplates,
        onCreate: createNewNote,
        onSaveDraft: saveNewNoteDraft,
        onSaveTemplate: saveNewNoteStartingTemplate,
        renderPreview: renderPaperPreview,
        renderNotebookPreview: renderNotebookPreview,
        onCancel: { showingNewNote = false })
        .presentationSizing(.page.fitted(horizontal: false, vertical: true))
    }
    .sheet(item: $libraryMutation) { request in
      LibraryMutationSheet(
        request: request,
        onApply: { name, parent in
          applyLibraryMutation(request, name: name, parent: parent)
        },
        onCancel: { libraryMutation = nil })
    }
    .sheet(item: $libraryDetails) { request in
      LibraryDetailsSheet(
        request: request,
        onSave: { description, tags, paper in
          saveLibraryDetails(
            request,
            description: description,
            tags: tags,
            paper: paper)
        },
        onCancel: { libraryDetails = nil })
    }
    .sheet(isPresented: $showingNewTag) {
      LibraryTagSheet(
        onAdd: addLibraryTag,
        onCancel: { showingNewTag = false })
    }
    .sheet(item: $pagePaper) { request in
      PagePaperSheet(
        request: request,
        onTemplate: applyPageTemplate,
        onPageSize: applyPageSize,
        onDone: { pagePaper = nil })
    }
    .sheet(isPresented: $showingPageOverview) {
      if let session, let viewState {
        PageOverviewSheet(
          document: session.document,
          currentPage: Binding(
            get: { viewState.currentPage },
            set: { viewState.currentPage = $0 }),
          onSelect: selectOverviewPage,
          onEdit: pageOverviewEdited,
          onError: { errorMessage = $0.localizedDescription },
          onDone: { showingPageOverview = false })
      }
    }
    .sheet(isPresented: $showingLayers) {
      if let session, let viewState {
        LayersSheet(
          document: session.document,
          activeLayerID: Binding(
            get: { viewState.activeLayerID },
            set: { viewState.activeLayerID = $0 }),
          onEdit: layerEdited,
          onError: { errorMessage = $0.localizedDescription },
          onDone: { showingLayers = false })
      }
    }
    .sheet(item: $goToPage) { request in
      GoToPageSheet(
        request: request,
        onGo: { page in
          currentPage = page
          pageNavigationRevision &+= 1
          goToPage = nil
        },
        onCancel: { goToPage = nil })
    }
    .sheet(item: $bookmarks) { request in
      BookmarksSheet(
        request: request,
        onSelect: selectBookmark,
        onCancel: cancelBookmarks)
    }
    .sheet(isPresented: $showingLinkChooser) {
      LinkSelectionSheet(
        onChoose: handleLinkChoice,
        onCancel: {
          showingLinkChooser = false
          pendingLink = nil
        })
    }
    .sheet(item: $figureEditor) { request in
      FigureEditorSheet(
        request: request,
        onDraft: { source, persistent in
          try updateFigureDraft(
            id: request.id,
            source: source,
            persistent: persistent)
        },
        onDismiss: {
          _ = openNotes.setCapture(viewID: request.viewID, active: false)
        })
    }
    .sheet(item: $conflictReview) { request in
      ConflictReviewSheet(
        request: request,
        onChoice: { choice in
          resolveConflict(request, choice: choice)
        },
        onCancel: { finishConflictReview(request.reference) })
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
      consumeIncomingDocument()
    }
    .onChange(of: sceneDelegate.incomingDocument) { _, _ in
      consumeIncomingDocument()
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        root?.resumeFilePresentation(refreshSavedLocation: true)
        refreshLibrary()
        reloadPenLibrary()
        if let root {
          for note in openNotes.opened {
            note.conflictCount = (try? root.conflictCount(note.reference)) ?? note.conflictCount
          }
        }
      case .background:
        flushPendingSaves()
        root?.suspendFilePresentation()
      default:
        break
      }
    }
    .overlay(alignment: .bottom) {
      if let toast = deletedPageToast, !openNotes.inLibrary {
        HStack(spacing: 12) {
          Text("Page \(toast.number) deleted")
          Button("Undo") {
            undoDeletedPage(toast)
          }
          .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
          UIAccessibility.post(
            notification: .announcement,
            argument: "Page \(toast.number) deleted")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 3)
        .padding(16)
      }
      if let libraryNotice, openNotes.inLibrary {
        Text(libraryNotice)
          .onAppear {
            UIAccessibility.post(notification: .announcement, argument: libraryNotice)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          .shadow(radius: 8, y: 3)
          .padding(16)
      }
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
  private var workspaceView: some View {
    VStack(spacing: 0) {
      if showTabStrip && openNotes.opened.count >= 2 {
        openNoteTabs
      }

      if openNotes.splitOpen {
        splitWorkspace
      } else {
        primaryEditors
      }
    }
    .background(NativeTheme.board)
    .foregroundStyle(NativeTheme.ink)
    .tint(NativeTheme.ink)
    .font(NativeTheme.body)
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(NativeTheme.board, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      if let session {
        ToolbarItem(placement: .principal) {
          Text(session.reference.name)
            .font(NativeTheme.headline)
            .foregroundStyle(NativeTheme.ink)
            .lineLimit(1)
        }
        ToolbarItem(placement: .topBarLeading) {
          Button(action: showLibrary) {
            Label("Library", systemImage: "chevron.left")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Text(viewState?.captureActive == true ? "Drawing in progress" : session.saveStatus.label)
            .font(NativeTheme.footnote)
            .foregroundStyle(NativeTheme.graphite)
            .accessibilityLabel("Notebook save")
            .accessibilityValue(
              viewState?.captureActive == true ? "Drawing in progress" : session.saveStatus.label)
            .onChange(of: session.saveStatus) { _, status in
              guard viewState?.captureActive != true else { return }
              UIAccessibility.post(
                notification: .announcement,
                argument: "Notebook save, \(status.label)")
            }
            .onChange(of: viewState?.captureActive) { _, active in
              UIAccessibility.post(
                notification: .announcement,
                argument: active == true
                  ? "Notebook save, Drawing in progress"
                  : "Notebook save, \(session.saveStatus.label)")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            prepareOpenNotePicker(.tab)
          } label: {
            Label("Open note", systemImage: "doc.badge.plus")
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
    }
  }

  @ViewBuilder
  private var splitWorkspace: some View {
    if let secondary = openNotes.secondary,
      let secondaryView = openNotes.secondaryView
    {
      ResizableEditorSplitView(
        axis: openNotes.splitAxis,
        fraction: $editorSplitFraction
      ) {
        primaryEditors
      } secondary: {
        VStack(spacing: 0) {
          HStack {
            Button {
              prepareOpenNotePicker(.reference)
            } label: {
              Label(
                "Reference: \(secondary.reference.name)",
                systemImage: "rectangle.split.2x1")
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)

            Spacer()

            Button {
              closeSplit()
            } label: {
              Image(systemName: "xmark")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close split")
          }
          .padding(.horizontal, 12)
          .frame(minHeight: 44)
          .background(NativeTheme.board)
          .foregroundStyle(NativeTheme.ink)
          .font(NativeTheme.callout)

          editorPane(
            secondary,
            viewState: secondaryView,
            active: !openNotes.inLibrary,
            focused: !openNotes.inLibrary && openNotes.rightFocused,
            right: true)
        }
      }
    }
  }

  @ViewBuilder
  private var primaryEditors: some View {
    ZStack {
      ForEach(openNotes.opened) { note in
        let isActive = openNotes.active?.id == note.id
        editorPane(
          note,
          viewState: note.primaryView,
          active: isActive,
          focused: isActive && !openNotes.rightFocused,
          right: false)
          .opacity(isActive ? 1 : 0)
          .allowsHitTesting(isActive)
          .accessibilityHidden(!isActive)
      }
    }
  }

  private func editorPane(
    _ note: OpenNotebookSession,
    viewState: OpenNotebookViewState,
    active: Bool,
    focused: Bool,
    right: Bool
  ) -> some View {
    HStack(spacing: 0) {
      NotebookEditorPane(
        session: note,
        viewState: viewState,
        active: active,
        focused: focused,
        linked: active && openNotes.splitOpen && openNotes.linkedViews,
        linkedViewport: openNotes.linkedViewport,
        arrangement: EditorPageArrangement.stored(pageArrangementRaw),
        fingerDraws: fingerDraws,
        hiddenTools: hiddenTools,
        penLibrary: $penLibrary,
        tool: $selectedTool,
        drawingTool: $selectedDrawingTool,
        eraserMode: $eraserMode,
        selectorMode: $selectorMode,
        spaceMode: $spaceMode,
        previousPencilTool: $previousPencilTool,
        onFocus: { openNotes.focusRight(right) },
        onViewportChanged: { openNotes.setLinkedViewport($0) },
        onEditCommitted: { scheduleNotebookSave(note) },
        onSaveRequested: { saveNotebook(note) },
        onPensChanged: persistPenLibrary,
        onInsertImage: {
          openNotes.focusRight(right)
          showingImageImporter = true
        },
        clippingsOpen: viewState.clippingsRequest != nil,
        onShowClippings: {
          openNotes.focusRight(right)
          if viewState.clippingsRequest != nil {
            dismissClippings(viewState: viewState)
          } else {
            prepareClippings(viewState: viewState)
          }
        },
        onSaveClipping: { svg in
          openNotes.focusRight(right)
          saveClipping(svg, viewState: viewState)
        },
        onLinkSelectionRequested: { page in
          openNotes.focusRight(right)
          prepareLink(note, viewState: viewState, sourcePage: page)
        },
        onFollowLink: { href, page in
          openNotes.focusRight(right)
          followLink(href, source: note, viewState: viewState, page: page)
        },
        onDropClipping: { id, point in
          openNotes.focusRight(right)
          return dropClipping(id, at: point, viewState: viewState)
        },
        onEditFigure: { id in
          openNotes.focusRight(right)
          openFigureEditor(id)
        },
        onError: { errorMessage = $0.localizedDescription })

      if let request = viewState.clippingsRequest {
        ClippingsSheet(
          request: request,
          selectionActive: viewState.selectionActive,
          drawing: viewState.captureActive,
          onInsert: { insertClipping($0, viewState: viewState) },
          onSaveSelection: { viewState.editorPageCommand = .saveSelectionToClippings },
          onSave: saveClippingDrop,
          onMove: moveClipping,
          onDelete: deleteClipping,
          onRefresh: { refreshClippings(viewState: viewState) },
          onClose: { dismissClippings(viewState: viewState) })
          .id(request.id)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
  }

  @ViewBuilder
  private var openNoteTabs: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(openNotes.opened) { note in
          let selected = openNotes.selected?.id == note.id
          HStack(spacing: 2) {
            Button {
              openNotebook(note.reference)
            } label: {
              Text(note.reference.name)
                .lineLimit(1)
                .font(selected ? NativeTheme.headline : NativeTheme.callout)
                .foregroundStyle(selected ? NativeTheme.ink : NativeTheme.graphite)
                .padding(.leading, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityLabel(note.reference.name)
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button {
              closeOpenNote(note.id)
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 14))
                .foregroundStyle(NativeTheme.graphite)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(note.reference.name)")
          }
          .background(
            selected ? NativeTheme.leaf : Color.clear,
            in: RoundedRectangle(cornerRadius: 8))
          .overlay(alignment: .trailing) {
            Rectangle()
              .fill(NativeTheme.separator)
              .frame(width: 1)
          }
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
    }
    .background(NativeTheme.board)
  }

  @ViewBuilder
  private func documentMenu(_ session: OpenNotebookSession) -> some View {
    let drawing = viewState?.captureActive == true
    Menu {
      Button {
        saveNotebook(session)
      } label: {
        Label(session.saveStatus == .failed ? "Retry save" : "Save", systemImage: "square.and.arrow.down")
      }
      .disabled(drawing)

      Button(PDFExportDestination.share.menuLabel, systemImage: "square.and.arrow.up") {
        preparePDFExport(session, destination: .share)
      }
      .disabled(drawing)

      Button(PDFExportDestination.export.menuLabel, systemImage: "folder") {
        preparePDFExport(session, destination: .export)
      }
      .disabled(drawing)

      if session.conflictCount > 0 {
        Button("Compare conflicting versions", systemImage: "exclamationmark.triangle") {
          prepareConflicts(session.reference)
        }
        .disabled(drawing)
      }

      Divider()
      if openNotes.rightFocused && openNotes.splitOpen {
        Button("Close note", systemImage: "rectangle.split.2x1") {
          closeSplit()
        }
        .disabled(drawing)
      } else {
        Button("Close note", systemImage: "xmark") {
          closeOpenNote(session.id)
        }
        .disabled(drawing)
      }

      Button("Settings", systemImage: "gearshape") {
        settingsFromLibrary = false
        showingEditorSettings = true
      }
    } label: {
      Label("More", systemImage: "ellipsis")
    }
  }

  @ViewBuilder
  private var viewMenu: some View {
    let selected = EditorPageArrangement.stored(pageArrangementRaw)
    Menu {
      Button {
        fitRevision &+= 1
      } label: {
        let label = selected == .horizontal ? "Fit height" : "Fit width"
        if viewState?.fitActive == true {
          Label(label, systemImage: "checkmark")
        } else {
          Label(
            label,
            systemImage: selected == .horizontal ? "arrow.up.and.down" : "arrow.left.and.right")
        }
      }
      .accessibilityAddTraits(viewState?.fitActive == true ? .isSelected : [])
      Divider()
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
        .accessibilityAddTraits(arrangement == selected ? .isSelected : [])
      }
      Divider()
      Button(
        openNotes.splitOpen ? "Close split view" : "Split view",
        systemImage: "rectangle.split.2x1"
      ) {
        toggleSplit()
      }
      if openNotes.splitOpen {
        Button {
          openNotes.toggleLinkedViews()
        } label: {
          if openNotes.linkedViews {
            Label("Link views", systemImage: "checkmark")
          } else {
            Label("Link views", systemImage: "link")
          }
        }
        .accessibilityAddTraits(openNotes.linkedViews ? .isSelected : [])
        Button("Rotate split", systemImage: "rectangle.2.swap") {
          openNotes.rotateSplit()
        }
      }
    } label: {
      Label("View", systemImage: "eye")
    }
  }
  @ViewBuilder
  private func pagesMenu(_ session: OpenNotebookSession) -> some View {
    let count = (try? session.document.pageCount()) ?? 0
    let availability = PageMenuAvailability(
      drawing: viewState?.captureActive == true,
      pageCount: count)
    Menu {
      Button("Page overview", systemImage: "square.grid.2x2") {
        showingPageOverview = true
      }
      .keyboardShortcut("p", modifiers: [.command, .shift])
      .disabled(!availability.pageOverview)
      Button("Go to page", systemImage: "number") {
        goToPage = GoToPageRequest(
          pageCount: count,
          currentPage: currentPage)
      }
      .disabled(!availability.goToPage)
      Divider()
      Button("Add page", systemImage: "plus.rectangle") {
        editPages(session) { document in
          try document.appendPage()
        }
      }
      .disabled(!availability.pageMutation)
      Button("Insert page before", systemImage: "rectangle.badge.plus") {
        editPages(session) { document in
          try document.insertPage(at: currentPage)
        }
      }
      .disabled(!availability.pageMutation)
      Button("Insert page after", systemImage: "rectangle.badge.plus") {
        editPages(session) { document in
          try document.insertPage(at: currentPage + 1)
        }
      }
      .disabled(!availability.pageMutation)
      Divider()
      Button("Select page", systemImage: "square.dashed") {
        editorPageCommand = .select(currentPage)
      }
      .disabled(!availability.selectPage)
      Button("Clear page", systemImage: "eraser") {
        editorPageCommand = .clear(currentPage)
      }
      .disabled(!availability.clearPage)
      Button("Paper for new pages", systemImage: "doc.text") {
        preparePagePaper(session)
      }
      .disabled(!availability.paper)
      Divider()
      Button("Bookmarks", systemImage: "bookmark") {
        prepareBookmarks(session)
      }
      .disabled(!availability.bookmarks)
      Button("Add bookmark", systemImage: "bookmark.fill") {
        editorPageCommand = .addBookmark
      }
      .disabled(!availability.addBookmark)
      Button("Layers", systemImage: "square.3.layers.3d") {
        showingLayers = true
      }
      .disabled(!availability.layers)
      Divider()
      Button("Delete page", systemImage: "trash", role: .destructive) {
        editPages(session) { document in
          let deleted = currentPage
          try document.deletePage(at: deleted)
          currentPage = min(deleted, max(0, try document.pageCount() - 1))
          showDeletedPageToast(
            number: deleted + 1,
            session: session,
            viewState: viewState ?? session.primaryView)
        }
      }
      .disabled(!availability.deletePage)
    } label: {
      Label("Pages", systemImage: "doc.on.doc")
    }
  }

  @ViewBuilder
  private func libraryView(root: NotesRootAccess) -> some View {
    NativeLibraryView(
      root: root,
      folder: libraryFolder,
      notebookOpen: libraryNotebookOpen,
      listing: libraryListing,
      folderDetails: libraryFolderDetails,
      query: $libraryQuery,
      scope: libraryScope,
      tags: libraryTags,
      tagCounts: libraryTagCounts,
      selectedTag: libraryTag,
      sort: librarySort,
      sortDirection: librarySortDirection,
      grid: libraryGrid,
      openFolder: { folder in
        libraryFolder = folder
        libraryNotebookOpen = true
        refreshLibrary()
      },
      openNotebook: openNotebook,
      goUp: {
        libraryFolder = FolderReference(path: [])
        libraryNotebookOpen = false
        refreshLibrary()
      },
      showSearch: {
        libraryTag = nil
        libraryScope = .folder
        libraryFolder = FolderReference(path: [])
        libraryNotebookOpen = false
        refreshLibrary()
      },
      selectScope: { next in
        libraryQuery = ""
        libraryTag = nil
        libraryFolder = FolderReference(path: [])
        libraryNotebookOpen = false
        if next == .recent {
          librarySort = .modified
          librarySortDirection = .descending
        }
        libraryScope = next
        refreshLibrary()
      },
      filterScope: { next in
        libraryTag = nil
        if next == .recent {
          librarySort = .modified
          librarySortDirection = .descending
        }
        libraryScope = next
        refreshLibrary()
      },
      setSort: { sort in
        librarySort = sort
        librarySortDirection = sort == .name ? .ascending : .descending
        refreshLibrary()
      },
      setSortDirection: { direction in
        librarySortDirection = direction
        refreshLibrary()
      },
      selectTag: { tag in
        libraryTag = tag
        libraryQuery = ""
        libraryFolder = FolderReference(path: [])
        libraryNotebookOpen = false
        libraryScope = .tag
        refreshLibrary()
      },
      filterTag: { tag in
        libraryTag = tag
        libraryScope = .tag
        refreshLibrary()
      },
      createTag: { showingNewTag = true },
      toggleLayout: { libraryGrid.toggle() },
      createNote: prepareNewNote,
      createNotebook: prepareNewNotebook,
      importPDF: { showingPDFImporter = true },
      renameEntry: { prepareLibraryMutation(.rename($0)) },
      moveEntry: { prepareLibraryMutation(.move($0)) },
      trashEntry: moveLibraryEntryToTrash,
      restoreEntry: { prepareLibraryMutation(.restore($0)) },
      toggleFavorite: toggleFavorite,
      editNoteDetails: prepareNoteDetails,
      editFolderDetails: prepareFolderDetails,
      reviewConflicts: reviewLibraryConflicts,
      refreshSearch: { refreshLibrary(recountTags: false) },
      showSettings: {
        settingsFromLibrary = true
        showingEditorSettings = true
      })
  }

  private func restoreSavedRoot() {
    guard !restoredRoot else { return }
    restoredRoot = true
    guard let restored = NotesRootAccess.restore() else { return }
    installRoot(restored)
  }

  private var needsRootReconnect: Bool {
    restoredRoot && NotesRootAccess.hasSavedRoot
  }

  private func selectRoot(_ url: URL) {
    do {
      installRoot(try NotesRootAccess(selectedURL: url), persistBookmark: true)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func makeOpenSession(
    _ reference: NotebookReference,
    using root: NotesRootAccess,
    currentPage: Int = 0
  ) throws -> OpenNotebookSession {
    let document = try root.load(reference)
    let pageCount = try document.pageCount()
    let session = OpenNotebookSession(
      reference: reference,
      document: document,
      conflictCount: try root.conflictCount(reference),
      saveStatus: root.hasRecoveredChanges(reference) ? .recoverable : .saved)
    session.currentPage = min(currentPage, max(0, pageCount - 1))
    return session
  }

  private func saveSession(
    _ session: OpenNotebookSession,
    using root: NotesRootAccess
  ) throws {
    try session.performSave {
      try root.save(session.document, notebook: session.reference)
      session.conflictCount = try root.conflictCount(session.reference)
    }
  }

  private func handleOpenNotesError(_ error: Error) {
    guard let stateError = error as? OpenNotesStateError else {
      errorMessage = error.localizedDescription
      return
    }

    switch stateError {
    case .captureInProgress:
      errorMessage = stateError.localizedDescription
    case let .saveFailed(reference, underlying):
      if let storageError = underlying as? NotebookStorageError {
        switch storageError {
        case .externalChanges:
          prepareConflicts(reference, saveOpen: false)
          return
        default:
          break
        }
      }
      errorMessage = underlying.localizedDescription
    }
  }

  private func flushPendingSaves() {
    guard let root else { return }
    do {
      try openNotes.savePending { note in
        try saveSession(note, using: root)
      }
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func saveNotebook(_ note: OpenNotebookSession) {
    guard let root else { return }
    do {
      try saveSession(note, using: root)
    } catch let storageError as NotebookStorageError {
      switch storageError {
      case .externalChanges:
        prepareConflicts(note.reference, saveOpen: false)
      default:
        errorMessage = storageError.localizedDescription
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func showLibrary() {
    guard let root else { return }
    do {
      try openNotes.showLibrary { note in
        try saveSession(note, using: root)
      }
      conflictReview = nil
      refreshLibrary()
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func prepareOpenNotePicker(_ purpose: OpenNotePickerPurpose) {
    guard let root else { return }
    do {
      openNoteChoices = try root.folders().flatMap { folder in
        try root.library(
          in: folder,
          overview: false,
          sort: .name,
          direction: .ascending).notebooks.sorted { left, right in
            left.reference.name.localizedCompare(right.reference.name) == .orderedAscending
          }
      }
      openNotePickerPurpose = purpose
      showingOpenNotePicker = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func closeOpenNote(_ id: UUID) {
    guard let root,
      let index = openNotes.opened.firstIndex(where: { $0.id == id })
    else { return }

    do {
      try openNotes.close(index) { note in
        try saveSession(note, using: root)
      }
      conflictReview = nil
      refreshLibrary()
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func closeOpenEntries(
    at path: [String],
    using root: NotesRootAccess
  ) throws {
    try openNotes.closeUnder(path) { note in
      try saveSession(note, using: root)
    }
  }

  private func installRoot(
    _ newRoot: NotesRootAccess,
    persistBookmark: Bool = false
  ) {
    if let root {
      do {
        try openNotes.closeAll { session in
          try saveSession(session, using: root)
        }
      } catch {
        handleOpenNotesError(error)
        return
      }
    } else {
      openNotes.reset()
    }

    do {
      try newRoot.prepareRoot()
      if persistBookmark {
        try newRoot.persistAsSavedRoot()
      }
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    conflictReview = nil
    libraryFolder = FolderReference(path: [])
    libraryNotebookOpen = false
    libraryTags = []
    libraryTagCounts = [:]
    libraryListing = LibraryListing(folders: [], notebooks: [])
    libraryFolderDetails = nil
    root = newRoot
    reloadPenLibrary()
    newRoot.onChange = { [weak newRoot] in
      guard let newRoot else { return }
      Task { @MainActor in
        openNotes.refreshConflictCounts { reference in
          try? newRoot.conflictCount(reference)
        }
        if openNotes.inLibrary {
          refreshLibrary()
          reloadPenLibrary()
        }
      }
    }
    refreshLibrary()
    if let pendingPDFImport {
      self.pendingPDFImport = nil
      Task { await importPDF(pendingPDFImport.url, scopedAccess: pendingPDFImport.scopedAccess) }
    }
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
    guard let root else {
      penLibrary = library
      return
    }
    do {
      try root.savePenLibrary(library)
      penLibrary = library
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refreshLibrary(recountTags: Bool = true) {
    guard let root else {
      libraryListing = LibraryListing(folders: [], notebooks: [])
      libraryFolderDetails = nil
      libraryTagCounts = [:]
      return
    }

    do {
      libraryTags = try root.libraryTags()
      if recountTags {
        let allNotesForTags = try root.allNotes(sort: .name, direction: .ascending)
        libraryTagCounts = allNotesForTags.notebooks.reduce(into: [:]) { counts, note in
          for tag in Set(note.details.tags) {
            counts[tag, default: 0] += 1
          }
        }
      }
      let queryIsEmpty = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      libraryFolderDetails = libraryNotebookOpen
        ? try root.folderDetails(for: libraryFolder)
        : nil
      if libraryNotebookOpen {
        libraryListing = try root.library(
          in: libraryFolder,
          overview: false,
          sort: librarySort,
          direction: librarySortDirection)
      } else if libraryScope == .tag, let libraryTag {
        libraryListing = try root.taggedLibrary(
          tag: libraryTag,
          query: libraryQuery,
          sort: librarySort,
          direction: librarySortDirection)
      } else if !libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if libraryScope == .trash {
          libraryListing = try root.trashNotes(
            query: libraryQuery,
            sort: librarySort,
            direction: librarySortDirection)
        } else {
          let listing = try root.searchLibrary(
            query: libraryQuery,
            sort: librarySort,
            direction: librarySortDirection)
          switch libraryScope {
          case .favorites:
            libraryListing = LibraryListing(
              folders: [],
              notebooks: listing.notebooks.filter(\.favorite))
          case .recent:
            libraryListing = LibraryListing(folders: [], notebooks: listing.notebooks)
          default:
            libraryListing = listing
          }
        }
      } else if libraryScope == .recent {
        libraryListing = try root.allNotes(
          sort: librarySort,
          direction: librarySortDirection)
      } else if libraryScope == .favorites {
        libraryListing = try root.favoriteNotes(
          sort: librarySort,
          direction: librarySortDirection)
      } else if libraryScope == .trash {
        libraryListing = try root.trashNotes(
          sort: librarySort,
          direction: librarySortDirection)
      } else {
        libraryListing = try root.library(
          in: libraryFolder,
          overview: !libraryNotebookOpen,
          sort: librarySort,
          direction: librarySortDirection)
      }
      if let session {
        session.conflictCount = (try? root.conflictCount(session.reference)) ?? 0
      }
    } catch {
      libraryFolderDetails = nil
      if recountTags { libraryTagCounts = [:] }
      if libraryNotebookOpen {
        libraryFolder = FolderReference(path: [])
        libraryNotebookOpen = false
        refreshLibrary(recountTags: false)
        return
      }
      if libraryScope == .folder,
        libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        do {
          libraryListing = try root.library(
            in: libraryFolder,
            overview: true,
            sort: librarySort,
            direction: librarySortDirection)
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
      case let .rename(entry):
        initialParent = FolderReference(path: Array(entry.path.dropLast()))
        folders = allFolders
      case let .move(entry):
        initialParent = FolderReference(path: Array(entry.path.dropLast()))
        folders = allFolders
      case .restore:
        initialParent = FolderReference(path: [])
        folders = allFolders
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
    libraryMutation = nil
    do {
      switch request.mode {
      case let .rename(entry):
        try closeOpenEntries(at: entry.path, using: root)
        let currentParent = FolderReference(path: Array(entry.path.dropLast()))
        let destination = try root.moveEntry(
          path: entry.path,
          toParent: currentParent,
          name: name)
        followLibraryMove(from: entry.path, to: destination)
      case let .move(entry):
        try closeOpenEntries(at: entry.path, using: root)
        let destination = try root.moveEntry(
          path: entry.path,
          toParent: parent,
          name: entry.name)
        followLibraryMove(from: entry.path, to: destination)
      case let .restore(entry):
        try closeOpenEntries(at: entry.path, using: root)
        let destination = try root.moveEntry(
          path: entry.path,
          toParent: parent,
          name: entry.name)
        followLibraryMove(from: entry.path, to: destination)
      }
      refreshLibrary()
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func libraryFolderIsInside(_ path: [String]) -> Bool {
    libraryNotebookOpen &&
      libraryFolder.path.count >= path.count &&
      Array(libraryFolder.path.prefix(path.count)) == path
  }

  private func followLibraryMove(from source: [String], to destination: [String]) {
    guard libraryFolderIsInside(source) else { return }
    libraryFolder = FolderReference(
      path: destination + Array(libraryFolder.path.dropFirst(source.count)))
  }

  private func moveLibraryEntryToTrash(_ entry: LibraryEntryTarget) {
    guard let root else { return }
    do {
      try closeOpenEntries(at: entry.path, using: root)
      _ = try root.moveToTrash(path: entry.path)
      if libraryFolderIsInside(entry.path) {
        libraryFolder = FolderReference(path: [])
        libraryNotebookOpen = false
      }
      refreshLibrary()
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func toggleFavorite(_ item: LibraryNotebookItem) {
    guard let root else { return }
    do {
      try root.setFavorite(!item.favorite, for: item.reference)
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func prepareNoteDetails(_ reference: NotebookReference) {
    guard let root else { return }
    do {
      libraryDetails = LibraryDetailsRequest(
        target: .note(reference, try root.noteDetails(for: reference)),
        knownTags: try root.libraryTags())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func prepareFolderDetails(_ reference: FolderReference) {
    guard let root else { return }
    do {
      libraryDetails = LibraryDetailsRequest(
        target: .folder(reference, try root.folderDetails(for: reference)),
        knownTags: try root.libraryTags())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func saveLibraryDetails(
    _ request: LibraryDetailsRequest,
    description: String,
    tags: [String],
    paper: String?
  ) {
    guard let root else { return }
    libraryDetails = nil
    do {
      switch request.target {
      case let .note(reference, current):
        try root.saveNoteDetails(
          LibraryNoteDetails(
            favorite: current.favorite,
            tags: tags,
            description: description),
          for: reference)
      case let .folder(reference, current):
        try root.saveFolderDetails(
          LibraryFolderDetails(
            description: description,
            paper: paper ?? current.paper,
            coverColor: current.coverColor,
            coverStyle: current.coverStyle,
            tags: tags),
          for: reference)
      }
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func addLibraryTag(_ name: String, _ color: String) {
    guard let root else { return }
    showingNewTag = false
    do {
      try root.addLibraryTag(name: name, color: color)
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func prepareNewNotebook() {
    guard let root else { return }
    libraryNotice = nil
    do {
      try openNotes.saveAll { note in
        try saveSession(note, using: root)
      }
      newNotebookFolders = try root.folders()
      newNotebookKnownTags = try root.libraryTags()
      newNotebookDefaults = try root.folderDetails(for: libraryFolder)
      showingNewNotebook = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func createNewNotebook(_ request: NewNotebookRequest) {
    guard let root else { return }
    showingNewNotebook = false
    do {
      let reference = try root.createFolder(
        parent: request.parent,
        name: request.title,
        details: request.details)
      libraryFolder = reference
      libraryNotebookOpen = true
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func prepareNewNote() {
    guard let root else { return }
    libraryNotice = nil
    do {
      try openNotes.saveAll { note in
        try saveSession(note, using: root)
      }
      newNoteFolders = try root.folders()
      newNoteTemplates = try root.templateNames()
      guard !newNoteTemplates.isEmpty else {
        throw NotebookStorageError.missingTemplate("blank")
      }
      newNoteKnownTags = try root.libraryTags()
      newNoteFolderDefaults = try root.folderDetails(for: libraryFolder)
      newNoteDraft = try root.newNoteDraft()
      newNoteStartingTemplates = try root.newNoteStartingTemplates()
      showingNewNote = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func renderNotebookPreview(_ folder: FolderReference) throws -> Data? {
    guard let root else { throw NotebookStorageError.cannotAccessRoot }
    let listing = try root.library(in: folder, sort: .modified, direction: .descending)
    guard let first = listing.notebooks.first else { return nil }
    return try root.thumbnail(first.reference)
  }

  private func renderPaperPreview(
    _ template: String,
    _ pageSize: InkPageSize,
    _ orientation: InkOrientation
  ) throws -> Data {
    guard let root else { throw NotebookStorageError.cannotAccessRoot }
    return try root.paperPreview(
      template: template,
      pageSize: pageSize,
      orientation: orientation)
  }

  private func saveNewNoteDraft(_ draft: NewNoteDraft) {
    guard let root else { return }
    showingNewNote = false
    do {
      try root.saveNewNoteDraft(draft)
      refreshLibrary()
      showLibraryNotice("Draft saved")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func saveNewNoteStartingTemplate(_ template: NewNoteStartingTemplate) {
    guard let root else { return }
    showingNewNote = false
    do {
      try root.saveNewNoteStartingTemplate(template)
      refreshLibrary()
      showLibraryNotice("Template saved")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func showLibraryNotice(_ message: String) {
    libraryNotice = message
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  private func consumeIncomingDocument() {
    guard let document = sceneDelegate.incomingDocument else { return }
    sceneDelegate.clearIncomingDocument(document.id)
    handleIncomingPDF(document.url)
  }

  private func handleIncomingPDF(_ url: URL) {
    guard UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .pdf) == true else {
      errorMessage = "Math Notes can import PDF files."
      return
    }
    let scopedAccess = url.startAccessingSecurityScopedResource()
    guard root != nil else {
      if let pendingPDFImport, pendingPDFImport.scopedAccess {
        pendingPDFImport.url.stopAccessingSecurityScopedResource()
      }
      pendingPDFImport = PendingPDFImport(url: url, scopedAccess: scopedAccess)
      return
    }
    Task { await importPDF(url, scopedAccess: scopedAccess) }
  }

  private func importPDF(_ url: URL, scopedAccess: Bool? = nil) async {
    let scoped = scopedAccess ?? url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    guard let root else { return }
    do {
      try openNotes.prepareForExternalImport { note in
        try saveSession(note, using: root)
      }
    } catch {
      handleOpenNotesError(error)
      return
    }

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

      conflictReview = nil
      openNotes.show(
        OpenNotebookSession(
          reference: reference,
          document: document))
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

  private func importImage(_ url: URL) {
    guard let session else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }

    do {
      let data = try Data(contentsOf: url)
      if url.pathExtension.lowercased() == "svg" {
        guard let svg = String(data: data, encoding: .utf8), svg.contains("<svg") else {
          throw EngineDocumentError.operation("Import SVG", "Invalid SVG document")
        }
        editorPageCommand = .pasteSVGAtCenter(svg, placeAtPointer: false)
        return
      }
      guard let image = UIImage(data: data), let cgImage = image.cgImage else {
        throw ImageImportError.invalidImageSize
      }
      let page = try session.document.pageRect(index: currentPage)
      let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
      let ext = url.pathExtension.lowercased()
      let mimeType: String
      let importedData: Data
      if ext == "png" || contentType == .png {
        mimeType = "image/png"
        importedData = data
      } else if ext == "jpg" || ext == "jpeg" || contentType == .jpeg {
        mimeType = "image/jpeg"
        importedData = data
      } else {
        guard let png = UIImage(cgImage: cgImage).pngData() else {
          throw ImageImportError.invalidImageSize
        }
        mimeType = "image/png"
        importedData = png
      }
      let svg = try imageImportSVG(
        data: importedData,
        mimeType: mimeType,
        imageSize: CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)),
        pageSize: page.size)
      editorPageCommand = .pasteSVGAtCenter(svg, placeAtPointer: false)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func createNewNote(_ request: NewNoteRequest) {
    guard let root else { return }
    showingNewNote = false
    do {
      let (reference, document) = try root.createNote(
        title: request.title,
        parent: request.parent,
        template: request.template,
        pageSize: request.pageSize,
        orientation: request.orientation)
      try root.completeNewNoteCreation(reference, tags: request.tags)
      conflictReview = nil
      openNotes.show(
        OpenNotebookSession(
          reference: reference,
          document: document))
      refreshLibrary()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openNotebook(_ reference: NotebookReference) {
    guard let root else { return }
    do {
      _ = try openNotes.open(
        reference,
        save: { note in
          try saveSession(note, using: root)
        },
        load: { reference in
          try makeOpenSession(reference, using: root)
        })
      conflictReview = nil
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func reviewLibraryConflicts(_ reference: NotebookReference) {
    guard let root else { return }
    do {
      _ = try openNotes.open(
        reference,
        save: { note in
          try saveSession(note, using: root)
        },
        load: { reference in
          try makeOpenSession(reference, using: root)
        })
      conflictReview = nil
      prepareConflicts(reference)
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func showReference(_ reference: NotebookReference) {
    guard let root else { return }
    do {
      _ = try openNotes.showReference(
        reference,
        save: { note in
          try saveSession(note, using: root)
        },
        load: { reference in
          try makeOpenSession(reference, using: root)
        })
      conflictReview = nil
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func toggleSplit() {
    do {
      try openNotes.toggleSplit()
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func closeSplit() {
    openNotes.closeSplit()
  }

  private func prepareBookmarks(_ session: OpenNotebookSession) {
    do {
      bookmarkMode = false
      bookmarkPickerPurpose = .navigate
      pendingLink = nil
      bookmarks = BookmarksRequest(
        destinations: try bookmarkDestinations(session.document))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func bookmarkDestinations(_ document: EngineDocument) throws -> [BookmarkDestination] {
    try document.navigation()
      .filter { $0.href.isEmpty && $0.hasPosition }
      .sorted {
        if $0.page != $1.page { return $0.page < $1.page }
        return ($0.y ?? 0) < ($1.y ?? 0)
      }
      .map { mark in
        BookmarkDestination(
          mark: mark,
          preview: mark.id.isEmpty ? nil : try? document.bookmarkPNG(id: mark.id))
      }
  }

  private func selectBookmark(_ mark: EngineNavigationMark) {
    bookmarks = nil
    switch bookmarkPickerPurpose {
    case .navigate:
      bookmarkMode = false
      currentPage = mark.page
      editorPageCommand = .jumpToMark(mark)
    case .link:
      guard let pending = pendingLink, let targetReference = pending.targetReference else {
        pendingLink = nil
        bookmarkPickerPurpose = .navigate
        return
      }
      do {
        let href = try NotebookLink.href(
          source: pending.sourceReference,
          sourceFile: pending.sourceFile,
          target: targetReference,
          mark: mark)
        pending.viewState.editorPageCommand = .linkSelection(href)
        pendingLink = nil
        bookmarkPickerPurpose = .navigate
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func cancelBookmarks() {
    bookmarks = nil
    if case .link = bookmarkPickerPurpose {
      pendingLink = nil
      bookmarkPickerPurpose = .navigate
    }
  }

  private func prepareLink(
    _ source: OpenNotebookSession,
    viewState: OpenNotebookViewState,
    sourcePage: Int
  ) {
    do {
      let sourceFile = try pageFile(source.document, page: sourcePage)
      pendingLink = PendingLink(
        sourceReference: source.reference,
        sourceFile: sourceFile,
        viewState: viewState,
        targetReference: nil)
      showingLinkChooser = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func handleLinkChoice(_ choice: LinkSelectionChoice) {
    guard let pending = pendingLink else { return }
    switch choice {
    case .sameNotebook:
      showingLinkChooser = false
      prepareLinkDestinations(pending.sourceReference)
    case .anotherNotebook:
      showingLinkChooser = false
      prepareOpenNotePicker(.linkTarget)
    case let .href(href):
      showingLinkChooser = false
      let destination = href.trimmingCharacters(in: .whitespacesAndNewlines)
      if destination.isEmpty {
        pendingLink = nil
      } else if !applyPendingLink(destination) {
        pendingLink = nil
      }
    }
  }

  private func prepareLinkDestinations(_ reference: NotebookReference) {
    guard let root, var pending = pendingLink else { return }
    do {
      let document: EngineDocument
      if let opened = openNotes.find(reference) {
        document = opened.document
      } else {
        document = try root.load(reference)
      }
      pending.targetReference = reference
      pendingLink = pending
      bookmarkPickerPurpose = .link
      bookmarks = BookmarksRequest(
        destinations: try bookmarkDestinations(document))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @discardableResult
  private func applyPendingLink(_ href: String) -> Bool {
    guard let pending = pendingLink else { return false }
    pending.viewState.editorPageCommand = .linkSelection(href)
    pendingLink = nil
    bookmarkPickerPurpose = .navigate
    return true
  }

  private func followLink(
    _ href: String,
    source: OpenNotebookSession,
    viewState: OpenNotebookViewState,
    page: Int
  ) {
    guard let root else { return }
    do {
      let sourceFile = try pageFile(source.document, page: page)
      switch try NotebookLink.resolve(
        source: source.reference,
        sourceFile: sourceFile,
        href: href)
      {
      case let .external(url):
        guard UIApplication.shared.canOpenURL(url) else {
          throw EngineDocumentError.operation(
            "Open link",
            "No application can open this link.")
        }
        UIApplication.shared.open(url, options: [:])

      case let .page(reference, file, id):
        let target = try openNotes.openLinkTarget(
          reference,
          save: { note in
            try saveSession(note, using: root)
          },
          load: { reference in
            try makeOpenSession(reference, using: root)
          })
        let targetDocument = target.document
        let targetView = target.primaryView

        let targetMarks = try targetDocument.navigation()
        guard let mark = targetMarks.first(where: { candidate in
          candidate.href.isEmpty
            && candidate.file == file
            && candidate.id == id
            && candidate.hasPosition
        }) else {
          throw EngineDocumentError.operation(
            "Open link",
            "The link destination is not in this notebook.")
        }
        targetView.currentPage = mark.page
        targetView.editorPageCommand = .jumpToMark(mark)
        conflictReview = nil
      }
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func pageFile(_ document: EngineDocument, page: Int) throws -> String {
    let marks = try document.navigation()
    guard let mark = marks.first(where: { candidate in
      candidate.page == page && candidate.id.isEmpty && candidate.href.isEmpty
    }) else {
      throw EngineDocumentError.operation(
        "Open link",
        "The source page is not in this notebook.")
    }
    return mark.file
  }

  private func openFigureEditor(_ id: String) {
    guard let session, let viewState else { return }
    do {
      let source = try session.document.figureSource(id: id)
      guard openNotes.setCapture(viewID: viewState.id, active: true) else {
        throw EngineDocumentError.operation(
          "Edit figure", "The figure pane is no longer open")
      }
      figureEditor = FigureEditorRequest(
        id: id,
        source: source,
        viewID: viewState.id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func updateFigureDraft(
    id: String,
    source: String,
    persistent: Bool
  ) throws {
    guard let session else { return }
    try session.document.saveFigureDraft(id: id, source: source)
    documentRevision &+= 1
    if persistent {
      session.markUnsaved()
      guard let root else { return }
      try saveSession(session, using: root)
    } else {
      scheduleNotebookSave(session)
    }
  }

  private func prepareConflicts(
    _ reference: NotebookReference,
    saveOpen: Bool = true
  ) {
    guard let root else { return }
    do {
      try openNotes.requireNoCapture("comparing versions")
      var conflicts = try root.conflicts(reference)
      if saveOpen, let session, session.reference == reference {
        do {
          try saveSession(session, using: root)
        } catch {
          conflicts = try root.conflicts(reference)
          if conflicts.isEmpty { throw error }
        }
      }

      openNotes.find(reference)?.conflictCount = conflicts.count
      guard let conflict = conflicts.first else {
        conflictReview = nil
        conflictReviewChanged = false
        return
      }
      conflictReviewChanged = false
      conflictReview = ConflictReviewRequest(
        reference: reference,
        conflict: conflict)
    } catch {
      handleOpenNotesError(error)
    }
  }

  private func resolveConflict(
    _ request: ConflictReviewRequest,
    choice: NotebookConflictChoice
  ) {
    guard let root else { return }
    do {
      try root.resolveConflict(
        request.reference,
        conflict: request.conflict,
        choice: choice)

      conflictReviewChanged = true
      let remaining = try root.conflicts(request.reference)
      openNotes.find(request.reference)?.conflictCount = remaining.count
      if let conflict = remaining.first {
        conflictReview = ConflictReviewRequest(
          reference: request.reference,
          conflict: conflict)
      } else {
        finishConflictReview(request.reference)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func finishConflictReview(_ reference: NotebookReference) {
    guard let root else {
      conflictReview = nil
      conflictReviewChanged = false
      return
    }
    do {
      let changed = conflictReviewChanged
      if changed, openNotes.find(reference) != nil {
        _ = try openNotes.reloadIfOpen(
          reference,
          save: { note in try saveSession(note, using: root) },
          load: { target in try makeOpenSession(target, using: root) })
      }
      conflictReview = nil
      conflictReviewChanged = false
      if changed { refreshLibrary() }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func clippingItems() throws -> [ClippingPreview] {
    guard let root else { return [] }
    return try root.clippingPreviews().enumerated().map {
      ClippingPreview(id: $0.element.id, index: $0.offset, png: $0.element.png)
    }
  }

  private func dismissClippings(viewState: OpenNotebookViewState) {
    viewState.clippingsRequest = nil
  }

  private func prepareClippings(viewState: OpenNotebookViewState) {
    do {
      viewState.clippingsRequest = ClippingsRequest(items: try clippingItems())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refreshClippings(viewState: OpenNotebookViewState) -> [ClippingPreview]? {
    do {
      let items = try clippingItems()
      viewState.clippingsRequest = ClippingsRequest(items: items)
      return items
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  private func saveClipping(_ svg: String, viewState: OpenNotebookViewState) {
    guard viewState.clippingsRequest != nil, saveClippingDrop(svg) else { return }
    _ = refreshClippings(viewState: viewState)
  }

  private func saveClippingDrop(_ svg: String) -> Bool {
    guard let root else { return false }
    do {
      try root.addClipping(svg: svg)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func insertClipping(_ id: String, viewState: OpenNotebookViewState) {
    guard let root else { return }
    do {
      viewState.editorPageCommand = .pasteSVGAtCenter(
        try root.clippingSVG(id: id),
        placeAtPointer: true)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func dropClipping(_ id: String, at point: CGPoint, viewState: OpenNotebookViewState) -> Bool {
    guard let root else { return false }
    do {
      viewState.editorPageCommand = .pasteSVG(
        try root.clippingSVG(id: id),
        at: point,
        placeAtPointer: true)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func moveClipping(_ id: String, _ offset: Int) -> Bool {
    guard let root else { return false }
    do {
      try root.moveClipping(id: id, by: offset)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func deleteClipping(_ id: String) -> Bool {
    guard let root else { return false }
    do {
      try root.deleteClipping(id: id)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func preparePDFExport(
    _ session: OpenNotebookSession,
    destination: PDFExportDestination
  ) {
    do {
      pdfExport = PDFExportRequest(
        sessionID: session.id,
        destination: destination,
        pageCount: try session.document.pageCount(),
        currentPage: currentPage,
        layers: try session.document.layers())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func finishPDFExport(
    _ session: OpenNotebookSession,
    destination: PDFExportDestination,
    firstPage: Int,
    pageCount: Int,
    layerIDs: [String]
  ) {
    guard let root else { return }
    do {
      try saveSession(session, using: root)
      let data = try session.document.exportPDF(
        title: session.reference.name,
        firstPage: firstPage,
        pageCount: pageCount,
        layerIDs: layerIDs)
      let url = try writeTemporaryPDFExport(data, name: session.reference.name)
      DispatchQueue.main.async {
        switch destination {
        case .share:
          sharePayload = SharePayload(url: url)
        case .export:
          exportPayload = ExportPayload(url: url)
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func preparePagePaper(_ session: OpenNotebookSession) {
    guard let root else { return }
    do {
      pagePaper = PagePaperRequest(
        templates: PagePaperSheet.sortedTemplates(try root.templateNames()),
        template: try root.templateName(for: session.reference),
        pageSize: try session.document.pageSize())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func applyPageTemplate(_ name: String) -> Bool {
    guard let root, let session else { return false }
    do {
      try root.applyTemplate(name: name, to: session.document)
      documentRevision &+= 1
      scheduleNotebookSave(session)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func applyPageSize(
    _ size: InkPageSize,
    _ orientation: InkOrientation,
    _ width: Double,
    _ height: Double
  ) -> Bool {
    guard let session else { return false }
    do {
      try session.document.setPageSize(
        size,
        orientation: orientation,
        width: width,
        height: height)
      documentRevision &+= 1
      scheduleNotebookSave(session)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
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
    if let session { scheduleNotebookSave(session) }
  }

  private func layerEdited() {
    documentRevision &+= 1
    if let session { scheduleNotebookSave(session) }
  }

  private func showDeletedPageToast(
    number: Int,
    session: OpenNotebookSession,
    viewState: OpenNotebookViewState
  ) {
    let toast = DeletedPageToast(session: session, viewState: viewState, number: number)
    deletedPageToast = toast
    UIAccessibility.post(notification: .announcement, argument: "Page \(number) deleted")
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(6))
      if deletedPageToast?.id == toast.id {
        deletedPageToast = nil
      }
    }
  }

  private func undoDeletedPage(_ toast: DeletedPageToast) {
    deletedPageToast = nil
    guard openNotes.opened.contains(where: { $0.id == toast.session.id }) else { return }
    do {
      guard let step = try toast.session.document.undo() else { return }
      let count = try toast.session.document.pageCount()
      toast.viewState.currentPage = min(max(step.page, 0), max(0, count - 1))
      toast.session.documentRevision &+= 1
      toast.viewState.pageNavigationRevision &+= 1
      scheduleNotebookSave(toast.session)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
  private func editPages(
    _ session: OpenNotebookSession,
    _ action: (EngineDocument) throws -> Void
  ) {
    do {
      try action(session.document)
      documentRevision &+= 1
      scheduleNotebookSave(session)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func scheduleNotebookSave(_ note: OpenNotebookSession) {
    note.scheduleAutosave(
      checkpoint: {
        guard let root else { throw NotebookStorageError.cannotAccessRoot }
        try root.checkpointRecovery(note.document, notebook: note.reference)
      }
    ) {
      saveNotebook(note)
    }
  }
}
