import InkEngine
import SwiftUI

struct NewNoteRequest {
  let title: String
  let parent: FolderReference
  let template: String
  let pageSize: InkPageSize
  let orientation: InkOrientation
}

private enum NewNotePageSize: String, CaseIterable, Identifiable {
  case a4 = "A4"
  case letter = "Letter"

  var id: Self { self }

  var engineValue: InkPageSize {
    switch self {
    case .a4: INK_PAGE_A4
    case .letter: INK_PAGE_LETTER
    }
  }
}

private enum NewNoteOrientation: String, CaseIterable, Identifiable {
  case portrait = "Portrait"
  case landscape = "Landscape"

  var id: Self { self }

  var engineValue: InkOrientation {
    switch self {
    case .portrait: INK_PORTRAIT
    case .landscape: INK_LANDSCAPE
    }
  }
}

struct NewNoteSheet: View {
  let folders: [FolderReference]
  let templates: [String]
  let onCreate: (NewNoteRequest) -> Void
  let onCancel: () -> Void

  @State private var title = ""
  @State private var parent: FolderReference
  @State private var template: String
  @State private var pageSize: NewNotePageSize = .a4
  @State private var orientation: NewNoteOrientation = .portrait

  init(
    folders: [FolderReference],
    templates: [String],
    initialParent: FolderReference? = nil,
    onCreate: @escaping (NewNoteRequest) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.folders = folders
    self.templates = templates
    self.onCreate = onCreate
    self.onCancel = onCancel
    let chosenParent = initialParent.flatMap { candidate in
      folders.contains(candidate) ? candidate : nil
    } ?? folders.first ?? FolderReference(path: [])
    _parent = State(initialValue: chosenParent)
    let initialTemplate = templates.contains("blank") ? "blank" : (templates.first ?? "blank")
    _template = State(initialValue: initialTemplate)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Note") {
          TextField("Title", text: $title)
            .textInputAutocapitalization(.sentences)
        }

        Section("Paper") {
          Picker("Paper style", selection: $template) {
            ForEach(templates, id: \.self) { name in
              Text(displayName(name)).tag(name)
            }
          }

          Picker("Page size", selection: $pageSize) {
            ForEach(NewNotePageSize.allCases) { size in
              Text(size.rawValue).tag(size)
            }
          }

          Picker("Orientation", selection: $orientation) {
            ForEach(NewNoteOrientation.allCases) { value in
              Text(value.rawValue).tag(value)
            }
          }
        }

        Section("Location") {
          Picker("Folder", selection: $parent) {
            ForEach(folders) { folder in
              Text(folder.name).tag(folder)
            }
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
            onCreate(
              NewNoteRequest(
                title: title,
                parent: parent,
                template: template,
                pageSize: pageSize.engineValue,
                orientation: orientation.engineValue))
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func displayName(_ template: String) -> String {
    template
      .replacingOccurrences(of: "-", with: " ")
      .capitalized
  }
}
