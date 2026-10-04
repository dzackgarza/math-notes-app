import InkEngine
import SwiftUI
import UIKit

struct NewNoteRequest {
  let title: String
  let parent: FolderReference
  let template: String
  let tags: [String]
  let pageSize: InkPageSize
  let orientation: InkOrientation
}

enum NewNotePageSize: String, CaseIterable, Identifiable {
  case a4
  case letter

  var id: Self { self }
  var label: String { self == .a4 ? "A4" : "Letter" }

  var engineValue: InkPageSize {
    switch self {
    case .a4: INK_PAGE_A4
    case .letter: INK_PAGE_LETTER
    }
  }

  init(persisted: String?) {
    self = NewNotePageSize(rawValue: persisted ?? "") ?? .a4
  }
}

enum NewNoteOrientation: String, CaseIterable, Identifiable {
  case portrait
  case landscape

  var id: Self { self }
  var label: String { rawValue.capitalized }

  var engineValue: InkOrientation {
    switch self {
    case .portrait: INK_PORTRAIT
    case .landscape: INK_LANDSCAPE
    }
  }

  init(persisted: String?) {
    self = NewNoteOrientation(rawValue: persisted ?? "") ?? .portrait
  }
}

enum NewNotePaperStyle {
  static let choices = ["dotted", "grid-medium", "lined-medium", "blank", "grid-fine"]

  static func shortLabel(_ name: String) -> String {
    switch name {
    case "dotted": "Dot"
    case "grid-medium": "Grid"
    case "lined-medium": "Lined"
    case "blank": "Plain"
    case "grid-fine": "Graph"
    default: name.replacingOccurrences(of: "-", with: " ").capitalized
    }
  }

  static func summaryLabel(_ name: String) -> String {
    switch name {
    case "dotted": "Dot paper"
    case "grid-medium": "Grid paper"
    case "lined-medium": "Lined paper"
    case "blank": "Plain paper"
    case "grid-fine": "Graph paper"
    case "lined-wide": "Lined paper, wide"
    case "lined-narrow": "Lined paper, narrow"
    case "grid-coarse": "Grid paper, coarse"
    default: name.replacingOccurrences(of: "-", with: " ").capitalized
    }
  }
}

struct NewNoteFormState: Equatable {
  var title: String
  var parent: FolderReference
  var template: String
  var tags: [String]
  var pageSize: NewNotePageSize
  var orientation: NewNoteOrientation

  init(
    folders: [FolderReference],
    templates: [String],
    initialParent: FolderReference?,
    folderDefaults: LibraryFolderDetails,
    draft: NewNoteDraft?
  ) {
    if let draft {
      title = draft.title
      parent = FolderReference(path: draft.folder)
      template = draft.template
      tags = draft.tags
      pageSize = NewNotePageSize(persisted: draft.pageSize)
      orientation = NewNoteOrientation(persisted: draft.orientation)
      return
    }

    title = ""
    parent = initialParent.flatMap { candidate in
      folders.contains(candidate) ? candidate : nil
    } ?? folders.first ?? FolderReference(path: [])
    template = folderDefaults.paper
    if template.isEmpty {
      template = templates.contains("blank") ? "blank" : (templates.first ?? "blank")
    }
    tags = folderDefaults.tags
    pageSize = .a4
    orientation = .portrait
  }

  mutating func apply(_ settings: NewNoteStartingTemplate) {
    parent = FolderReference(path: settings.folder)
    template = settings.paper
    tags = settings.tags
    pageSize = NewNotePageSize(persisted: settings.pageSize)
    orientation = NewNoteOrientation(persisted: settings.orientation)
  }

  var request: NewNoteRequest {
    NewNoteRequest(
      title: title,
      parent: parent,
      template: template,
      tags: tags,
      pageSize: pageSize.engineValue,
      orientation: orientation.engineValue)
  }

  var draft: NewNoteDraft {
    NewNoteDraft(
      folder: parent.path,
      title: title.trimmingCharacters(in: .whitespacesAndNewlines),
      template: template,
      tags: tags,
      pageSize: pageSize.rawValue,
      orientation: orientation.rawValue)
  }

  func startingTemplate(named name: String) -> NewNoteStartingTemplate {
    NewNoteStartingTemplate(
      name: name,
      folder: parent.path,
      paper: template,
      pageSize: pageSize.rawValue,
      orientation: orientation.rawValue,
      tags: tags)
  }
}


@MainActor
struct NewNoteSheet: View {
  let folders: [FolderReference]
  let knownTags: [LibraryTag]
  let startingTemplates: [NewNoteStartingTemplate]
  let onCreate: (NewNoteRequest) -> Void
  let onSaveDraft: (NewNoteDraft) -> Void
  let onSaveTemplate: (NewNoteStartingTemplate) -> Void
  let renderPreview: (String, InkPageSize, InkOrientation) throws -> Data
  let renderNotebookPreview: (FolderReference) throws -> Data?
  let onCancel: () -> Void

  @State private var form: NewNoteFormState
  private let openedForm: NewNoteFormState
  @State private var newTag = ""
  @State private var namingTemplate = false
  @State private var templateName = ""
  @State private var showingDiscardConfirmation = false

  init(
    folders: [FolderReference],
    templates: [String],
    knownTags: [LibraryTag],
    initialParent: FolderReference? = nil,
    folderDefaults: LibraryFolderDetails,
    draft: NewNoteDraft?,
    startingTemplates: [NewNoteStartingTemplate],
    onCreate: @escaping (NewNoteRequest) -> Void,
    onSaveDraft: @escaping (NewNoteDraft) -> Void,
    onSaveTemplate: @escaping (NewNoteStartingTemplate) -> Void,
    renderPreview: @escaping (String, InkPageSize, InkOrientation) throws -> Data,
    renderNotebookPreview: @escaping (FolderReference) throws -> Data?,
    onCancel: @escaping () -> Void
  ) {
    self.folders = folders
    self.knownTags = knownTags
    self.startingTemplates = startingTemplates
    self.onCreate = onCreate
    self.onSaveDraft = onSaveDraft
    self.onSaveTemplate = onSaveTemplate
    self.renderPreview = renderPreview
    self.renderNotebookPreview = renderNotebookPreview
    self.onCancel = onCancel
    let initialForm = NewNoteFormState(
      folders: folders,
      templates: templates,
      initialParent: initialParent,
      folderDefaults: folderDefaults,
      draft: draft)
    openedForm = initialForm
    _form = State(initialValue: initialForm)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Note") {
          TextField("Title", text: $form.title)
            .textInputAutocapitalization(.sentences)
            .nativeFieldSurface()
        }

        Section("Paper") {
          Picker("Paper style", selection: $form.template) {
            ForEach(NewNotePaperStyle.choices, id: \.self) { name in
              Text(NewNotePaperStyle.shortLabel(name)).tag(name)
            }
          }
          .pickerStyle(.segmented)

          Picker("Page size", selection: $form.pageSize) {
            ForEach(NewNotePageSize.allCases) { size in
              Text(size.label).tag(size)
            }
          }
          .pickerStyle(.segmented)

          Picker("Orientation", selection: $form.orientation) {
            ForEach(NewNoteOrientation.allCases) { value in
              Text(value.label).tag(value)
            }
          }
          .pickerStyle(.segmented)
        }

        Section("Preview") {
          CreationPaperPreview(
            template: form.template,
            pageSize: form.pageSize,
            orientation: form.orientation,
            render: renderPreview)
            .frame(maxWidth: .infinity)
            .frame(height: 280)
        }

        Section("Tags") {
          ForEach(tagNames, id: \.self) { name in
            Toggle(name, isOn: tagBinding(name))
          }
          HStack {
            TextField("New tag", text: $newTag)
              .textInputAutocapitalization(.never)
              .nativeFieldSurface()
              .onSubmit(addTag)
            Button("Add", action: addTag)
              .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }

        Section("Notebook") {
          CreationNotebookPreview(folder: form.parent, render: renderNotebookPreview)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
          Picker("Change notebook", selection: $form.parent) {
            ForEach(availableFolders) { folder in
              Text(folder.name).tag(folder)
            }
          }
        }

        if !startingTemplates.isEmpty || namingTemplate {
          Section("Starting template") {
            ForEach(startingTemplates) { settings in
              Button {
                form.apply(settings)
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(settings.name)
                  Text(templateSummary(settings))
                    .font(NativeTheme.footnote)
                    .foregroundStyle(NativeTheme.graphite)
                }
              }
            }

            if namingTemplate {
              HStack {
                TextField("Template name", text: $templateName)
                  .nativeFieldSurface()
                Button("Save") {
                  saveTemplate()
                }
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              }
            }
          }
        }

        Section {
          if !namingTemplate {
            Button("Save as template") {
              namingTemplate = true
            }
          }
          Button("Save as draft") {
            onSaveDraft(form.draft)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(NativeTheme.leaf)
      .foregroundStyle(NativeTheme.ink)
      .font(NativeTheme.body)
      .tint(NativeTheme.ink)
      .navigationTitle(newNoteTitle)
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
        "Discard new note?",
        isPresented: $showingDiscardConfirmation,
        titleVisibility: .visible
      ) {
        Button("Discard", role: .destructive, action: onCancel)
        Button("Keep Editing", role: .cancel) {}
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(NativeTheme.leaf, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: requestCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            onCreate(form.request)
          }
          .disabled(form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  var newNoteTitle: String {
    "New Note in \(form.parent.name)"
  }

  var isDirty: Bool {
    form != openedForm || !newTag.isEmpty || namingTemplate || !templateName.isEmpty
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

  private var tagNames: [String] {
    var result = knownTags.map(\.name)
    for name in form.tags where !result.contains(name) {
      result.append(name)
    }
    return result
  }

  private func tagBinding(_ name: String) -> Binding<Bool> {
    Binding(
      get: { form.tags.contains(name) },
      set: { selected in
        if selected {
          if !form.tags.contains(name) { form.tags.append(name) }
        } else {
          form.tags.removeAll { $0 == name }
        }
      })
  }

  private func addTag() {
    let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    if !form.tags.contains(name) { form.tags.append(name) }
    newTag = ""
  }

  private func saveTemplate() {
    let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    onSaveTemplate(form.startingTemplate(named: name))
  }

  private func templateSummary(_ settings: NewNoteStartingTemplate) -> String {
    let paper = NewNotePaperStyle.summaryLabel(settings.paper)
    let tags = "\(settings.tags.count) tag\(settings.tags.count == 1 ? "" : "s")"
    return "\(paper) · \(settings.pageSize.uppercased()) · \(tags)"
  }
}

@MainActor
struct CreationPaperPreview: View {
  let template: String
  let pageSize: NewNotePageSize
  let orientation: NewNoteOrientation
  let render: (String, InkPageSize, InkOrientation) throws -> Data

  @State private var image: UIImage?
  @State private var errorMessage: String?

  private var key: String {
    "\(template)|\(pageSize.rawValue)|\(orientation.rawValue)"
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6)
        .fill(NativeTheme.paper)

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .accessibilityLabel("First page preview")
      } else if let errorMessage {
        VStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle")
          Text("Preview failed")
            .font(NativeTheme.headline)
          Text(errorMessage)
            .font(NativeTheme.footnote)
            .foregroundStyle(NativeTheme.graphite)
            .multilineTextAlignment(.center)
        }
        .padding()
      } else {
        ProgressView()
          .accessibilityLabel("Loading first page preview")
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .stroke(NativeTheme.separator, lineWidth: 1)
    }
    .task(id: key) {
      image = nil
      errorMessage = nil
      do {
        let data = try render(
          template,
          pageSize.engineValue,
          orientation.engineValue)
        guard let rendered = UIImage(data: data) else {
          errorMessage = "The rendered preview was not a valid image."
          return
        }
        image = rendered
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

@MainActor
struct CreationNotebookPreview: View {
  let folder: FolderReference
  let render: (FolderReference) throws -> Data?

  @State private var image: UIImage?
  @State private var failed = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6)
        .fill(NativeTheme.paper)
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .accessibilityLabel("\(folder.name) thumbnail")
      } else if failed {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(NativeTheme.graphite)
          .accessibilityLabel("Notebook thumbnail failed")
      } else {
        Image(systemName: "book.closed")
          .font(NativeTheme.largeTitle)
          .foregroundStyle(NativeTheme.graphite)
          .accessibilityLabel("\(folder.name) notebook")
      }
    }
    .task(id: folder.id) {
      image = nil
      failed = false
      do {
        if let data = try render(folder) {
          image = UIImage(data: data)
        } else {
          image = nil
        }
      } catch {
        image = nil
        failed = true
      }
    }
  }
}
