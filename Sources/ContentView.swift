import SwiftUI

@MainActor
private struct NotebookSession {
  let reference: NotebookReference
  let document: EngineDocument
}

@MainActor
struct ContentView: View {
  @State private var root: NotesRootAccess?
  @State private var notebooks: [NotebookReference] = []
  @State private var session: NotebookSession?
  @State private var showingFolderPicker = false
  @State private var restoredRoot = false
  @State private var errorMessage: String?
  @State private var selectedTool: EditorTool = .pen
  @State private var currentPage = 0
  @State private var documentRevision = 0

  var body: some View {
    NavigationStack {
      Group {
        if let session {
          InkEditorView(
            document: session.document,
            tool: $selectedTool,
            currentPage: $currentPage,
            documentRevision: $documentRevision,
            onEditCommitted: saveOpenNotebook,
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
  }

  @ViewBuilder
  private func pagesMenu(_ session: NotebookSession) -> some View {
    let count = (try? session.document.pageCount()) ?? 0
    Menu {
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
    if notebooks.isEmpty {
      ContentUnavailableView {
        Label("No Notebooks", systemImage: "book.closed")
      } description: {
        Text("No folders containing notebook.json were found in \(root.url.lastPathComponent).")
      } actions: {
        Button("Rescan") {
          refreshLibrary()
        }
      }
      .navigationTitle("Math Notes")
      .toolbar {
        libraryToolbar
      }
    } else {
      List(notebooks) { notebook in
        Button {
          openNotebook(notebook)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "book.closed")
            VStack(alignment: .leading, spacing: 2) {
              Text(notebook.name)
              if notebook.path.count > 1 {
                Text(notebook.path.dropLast().joined(separator: " / "))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .buttonStyle(.plain)
      }
      .navigationTitle(root.url.lastPathComponent)
      .toolbar {
        libraryToolbar
      }
    }
  }

  @ToolbarContentBuilder
  private var libraryToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        showingFolderPicker = true
      } label: {
        Label("Change Folder", systemImage: "folder")
      }
    }
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
    root = newRoot
    newRoot.onChange = {
      Task { @MainActor in
        refreshLibrary()
      }
    }
    refreshLibrary()
  }

  private func refreshLibrary() {
    guard let root else {
      notebooks = []
      return
    }

    do {
      notebooks = try root.notebooks()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openNotebook(_ reference: NotebookReference) {
    guard let root else { return }
    do {
      currentPage = 0
      documentRevision = 0
      session = NotebookSession(
        reference: reference,
        document: try root.load(reference))
    } catch {
      errorMessage = error.localizedDescription
    }
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

  private func saveOpenNotebook() {
    guard let root, let session else { return }
    do {
      try root.save(session.document, notebook: session.reference)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
