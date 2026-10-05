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
          ZStack(alignment: .topLeading) {
            if description.isEmpty {
              Text("Description")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }
            TextEditor(text: $description)
              .frame(minHeight: 100)
              .accessibilityLabel("Description")
              .onChange(of: description) { _, value in
                if value.count > 500 {
                  description = String(value.prefix(500))
                }
              }
          }
          Text("\(description.count) / 500")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Tags") {
          EditableTagEditor(tags: $selectedTags, input: $newTag)
        }

        if request.target.paper != nil {
          Section("Default paper") {
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
      .navigationTitle(request.target.paper == nil ? request.target.title : "\(request.target.title) details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save details") {
            onSave(
              description,
              finalizedTagValues(selectedTags, pendingInput: newTag),
              request.target.paper == nil ? nil : paper)
          }
        }
      }
    }
  }

}
