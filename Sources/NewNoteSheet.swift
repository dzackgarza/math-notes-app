import InkEngine
import SwiftUI

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

struct NewNoteSheet: View {
  let folders: [FolderReference]
  let templates: [String]
  let knownTags: [LibraryTag]
  let startingTemplates: [NewNoteStartingTemplate]
  let onCreate: (NewNoteRequest) -> Void
  let onSaveDraft: (NewNoteDraft) -> Void
  let onSaveTemplate: (NewNoteStartingTemplate) -> Void
  let onCancel: () -> Void

  @State private var form: NewNoteFormState
  @State private var newTag = ""
  @State private var namingTemplate = false
  @State private var templateName = ""

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
    onCancel: @escaping () -> Void
  ) {
    self.folders = folders
    self.templates = templates
    self.knownTags = knownTags
    self.startingTemplates = startingTemplates
    self.onCreate = onCreate
    self.onSaveDraft = onSaveDraft
    self.onSaveTemplate = onSaveTemplate
    self.onCancel = onCancel
    _form = State(
      initialValue: NewNoteFormState(
        folders: folders,
        templates: templates,
        initialParent: initialParent,
        folderDefaults: folderDefaults,
        draft: draft))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Note") {
          TextField("Title", text: $form.title)
            .textInputAutocapitalization(.sentences)
        }

        Section("Paper") {
          Picker("Paper style", selection: $form.template) {
            ForEach(availableTemplates, id: \.self) { name in
              Text(displayName(name)).tag(name)
            }
          }

          Picker("Page size", selection: $form.pageSize) {
            ForEach(NewNotePageSize.allCases) { size in
              Text(size.label).tag(size)
            }
          }

          Picker("Orientation", selection: $form.orientation) {
            ForEach(NewNoteOrientation.allCases) { value in
              Text(value.label).tag(value)
            }
          }
        }

        Section("Tags") {
          ForEach(tagNames, id: \.self) { name in
            Toggle(name, isOn: tagBinding(name))
          }
          HStack {
            TextField("New tag", text: $newTag)
              .textInputAutocapitalization(.never)
              .onSubmit(addTag)
            Button("Add", action: addTag)
              .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }

        Section("Location") {
          Picker("Folder", selection: $form.parent) {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }

            if namingTemplate {
              HStack {
                TextField("Template name", text: $templateName)
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
      .navigationTitle("New Note")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
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

  private var availableFolders: [FolderReference] {
    folders.contains(form.parent) ? folders : [form.parent] + folders
  }

  private var availableTemplates: [String] {
    templates.contains(form.template) ? templates : [form.template] + templates
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

  private func displayName(_ template: String) -> String {
    template
      .replacingOccurrences(of: "-", with: " ")
      .capitalized
  }

  private func templateSummary(_ settings: NewNoteStartingTemplate) -> String {
    let paper = displayName(settings.paper)
    let tags = "\(settings.tags.count) tag\(settings.tags.count == 1 ? "" : "s")"
    return "\(paper) · \(settings.pageSize.uppercased()) · \(tags)"
  }
}
