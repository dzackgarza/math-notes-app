import InkEngine
import SwiftUI

struct NewNotebookRequest {
  let title: String
  let parent: FolderReference
  let details: LibraryFolderDetails
}

struct NewNotebookFormState: Equatable {
  static let paperStyles = ["dotted", "grid-medium", "blank", "lined-medium"]
  static let coverColorOrder = ["#24324A", "#5B2328", "#2F4A3A", "#A87B2C"]
  static let coverColors = [
    "#24324A": "Navy",
    "#5B2328": "Oxblood",
    "#2F4A3A": "Forest",
    "#A87B2C": "Ochre",
  ]

  var title = ""
  var description = ""
  var parent: FolderReference
  var paper: String
  var tags: [String]
  var coverColor: String
  var coverStyle: String

  init(
    folders: [FolderReference],
    initialParent: FolderReference?,
    defaults: LibraryFolderDetails
  ) {
    parent = initialParent.flatMap { candidate in
      folders.contains(candidate) ? candidate : nil
    } ?? folders.first ?? FolderReference(path: [])
    paper = defaults.paper
    tags = defaults.tags
    coverColor = defaults.coverColor
    coverStyle = defaults.coverStyle
  }

  var request: NewNotebookRequest {
    NewNotebookRequest(
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      parent: parent,
      details: LibraryFolderDetails(
        description: description,
        paper: paper,
        coverColor: coverColor,
        coverStyle: coverStyle,
        tags: tags))
  }
}

@MainActor
struct NewNotebookSheet: View {
  let folders: [FolderReference]
  let knownTags: [LibraryTag]
  let renderPreview: (String, InkPageSize, InkOrientation) throws -> Data
  let onCreate: (NewNotebookRequest) -> Void
  let onCancel: () -> Void

  @State private var form: NewNotebookFormState
  private let openedForm: NewNotebookFormState
  @State private var newTag = ""
  @State private var showingDiscardConfirmation = false
  @FocusState private var titleFocused: Bool

  init(
    folders: [FolderReference],
    knownTags: [LibraryTag],
    initialParent: FolderReference? = nil,
    defaults: LibraryFolderDetails,
    renderPreview: @escaping (String, InkPageSize, InkOrientation) throws -> Data,
    onCreate: @escaping (NewNotebookRequest) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.folders = folders
    self.knownTags = knownTags
    self.renderPreview = renderPreview
    self.onCreate = onCreate
    self.onCancel = onCancel
    let initialForm = NewNotebookFormState(
      folders: folders,
      initialParent: initialParent,
      defaults: defaults)
    openedForm = initialForm
    _form = State(initialValue: initialForm)
  }

  var body: some View {
    NavigationStack {
      CreationSheetLayout {
        notebookFormFields
      } preview: {
        NotebookCoverArt(
          color: NativeTheme.color(form.coverColor),
          edgeColor: NativeTheme.coverEdge(form.coverColor),
          style: form.coverStyle,
          title: form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled notebook"
            : form.title
        ) {
          CreationPaperPreview(
            template: form.paper,
            pageSize: .a4,
            orientation: .portrait,
            render: renderPreview)
        }
        .aspectRatio(0.7, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .scrollContentBackground(.hidden)
      .background(NativeTheme.leaf)
      .foregroundStyle(NativeTheme.ink)
      .font(NativeTheme.body)
      .tint(NativeTheme.ink)
      .navigationTitle("New notebook")
      .interactiveDismissDisabled(isDirty)
      .background {
        if isDirty {
          CreationDismissGuard {
            showingDiscardConfirmation = true
          }
          .frame(width: 0, height: 0)
        }
      }
      .confirmationDialog(
        "Discard new notebook?",
        isPresented: $showingDiscardConfirmation,
        titleVisibility: .visible
      ) {
        Button("Discard", role: .destructive, action: onCancel)
        Button("Keep editing", role: .cancel) {}
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(NativeTheme.leaf, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: requestCancel)
        }
        ToolbarItemGroup(placement: .bottomBar) {
          Spacer()
          Button("Create") {
            onCreate(finalizedForm.request)
          }
          .buttonStyle(.borderedProminent)
          .disabled(form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  @ViewBuilder
  private var notebookFormFields: some View {
    Section("Notebook") {
      TextField("Notebook title", text: $form.title)
        .textInputAutocapitalization(.sentences)
        .focused($titleFocused)
        .task { titleFocused = true }
        .nativeFieldSurface()

      ZStack(alignment: .topLeading) {
        if form.description.isEmpty {
          Text("Description")
            .foregroundStyle(NativeTheme.graphite)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
        }
        TextEditor(text: $form.description)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 72)
          .nativeFieldSurface()
          .accessibilityLabel("Description")
          .onChange(of: form.description) { _, value in
            if value.count > 500 {
              form.description = String(value.prefix(500))
            }
          }
      }
      Text("Description (optional) · \(form.description.count) / 500")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)
    }

    Section("Cover") {
      Picker("Cover style", selection: $form.coverStyle) {
        Text("Classic").tag("classic")
        Text("Spine").tag("spine")
      }
      .pickerStyle(.segmented)

      Text("Cover color")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)

      HStack(spacing: 12) {
        ForEach(NewNotebookFormState.coverColorOrder, id: \.self) { color in
          Button {
            form.coverColor = color
          } label: {
            Circle()
              .fill(colorValue(color))
              .frame(width: 30, height: 30)
              .overlay {
                if form.coverColor == color {
                  Circle()
                    .stroke(NativeTheme.ribbon, lineWidth: 2)
                    .padding(-4)
                }
              }
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(NewNotebookFormState.coverColors[color] ?? color)
          .accessibilityAddTraits(form.coverColor == color ? .isSelected : [])
        }
      }
    }

    Section("Paper") {
      Picker("Paper style", selection: $form.paper) {
        ForEach(NewNotebookFormState.paperStyles, id: \.self) { paper in
          Text(paperLabel(paper)).tag(paper)
        }
      }
      .pickerStyle(.segmented)
    }

    Section("Tags") {
      EditableTagEditor(tags: $form.tags, input: $newTag)
    }

    Section("Location") {
      Picker("Folder", selection: $form.parent) {
        ForEach(availableFolders) { folder in
          Text(folder.name).tag(folder)
        }
      }
      Text("You can move this notebook later.")
        .font(NativeTheme.footnote)
        .foregroundStyle(NativeTheme.graphite)
    }
  }

  var isDirty: Bool {
    form != openedForm || finalizedTagValues(form.tags, pendingInput: newTag) != form.tags
  }

  private func requestCancel() {
    if isDirty {
      showingDiscardConfirmation = true
    } else {
      onCancel()
    }
  }

  private var availableFolders: [FolderReference] {
    folders.contains(form.parent) ? folders : [form.parent] + folders
  }

  private var finalizedForm: NewNotebookFormState {
    var next = form
    next.tags = finalizedTagValues(form.tags, pendingInput: newTag)
    return next
  }

  private func paperLabel(_ paper: String) -> String {
    switch paper {
    case "dotted": "Dot"
    case "grid-medium": "Grid"
    case "blank": "Plain"
    case "lined-medium": "Lined"
    default: paper.replacingOccurrences(of: "-", with: " ").capitalized
    }
  }

  private func colorValue(_ value: String) -> Color {
    NativeTheme.color(value)
  }
}
