import Foundation
import SwiftUI

enum LibraryDetailsTarget {
  case note(NotebookReference, LibraryNoteDetails)
  case folder(FolderReference, LibraryFolderDetails)

  var title: String {
    switch self {
    case let .note(reference, _): reference.name
    case let .folder(reference, _): reference.name
    }
  }

  var description: String {
    switch self {
    case let .note(_, details): details.description
    case let .folder(_, details): details.description
    }
  }

  var tags: [String] {
    switch self {
    case let .note(_, details): details.tags
    case let .folder(_, details): details.tags
    }
  }

  var paper: String? {
    switch self {
    case .note: nil
    case let .folder(_, details): details.paper
    }
  }
}

struct LibraryDetailsRequest: Identifiable {
  let id = UUID()
  let target: LibraryDetailsTarget
  let knownTags: [LibraryTag]
}

struct LibraryDetailsSheet: View {
  let request: LibraryDetailsRequest
  let onSave: (String, [String], String?) -> Void
  let onCancel: () -> Void

  @State private var description: String
  @State private var selectedTags: [String]
  @State private var newTag = ""
  @State private var paper: String

  init(
    request: LibraryDetailsRequest,
    onSave: @escaping (String, [String], String?) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.request = request
    self.onSave = onSave
    self.onCancel = onCancel
    _description = State(initialValue: request.target.description)
    _selectedTags = State(initialValue: request.target.tags)
    _paper = State(initialValue: request.target.paper ?? "dotted")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Description") {
          TextEditor(text: $description)
            .frame(minHeight: 100)
            .onChange(of: description) { _, value in
              if value.count > 500 {
                description = String(value.prefix(500))
              }
            }
          Text("\(description.count) / 500")
            .font(.caption)
            .foregroundStyle(.secondary)
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

        if request.target.paper != nil {
          Section("Default Paper") {
            Picker("Paper", selection: $paper) {
              Text("Dot").tag("dotted")
              Text("Graph").tag("grid-medium")
              Text("Blank").tag("blank")
              Text("Ruled").tag("lined-medium")
            }
            .pickerStyle(.segmented)
          }
        }
      }
      .navigationTitle("\(request.target.title) Details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(description, selectedTags, request.target.paper == nil ? nil : paper)
          }
        }
      }
    }
  }

  private var tagNames: [String] {
    var result = request.knownTags.map(\.name)
    for name in selectedTags where !result.contains(name) {
      result.append(name)
    }
    return result
  }

  private func tagBinding(_ name: String) -> Binding<Bool> {
    Binding(
      get: { selectedTags.contains(name) },
      set: { selected in
        if selected {
          if !selectedTags.contains(name) { selectedTags.append(name) }
        } else {
          selectedTags.removeAll { $0 == name }
        }
      })
  }

  private func addTag() {
    let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    if !selectedTags.contains(name) { selectedTags.append(name) }
    newTag = ""
  }
}
