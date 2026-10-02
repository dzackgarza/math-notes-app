import SwiftUI

enum LibraryEntryKind: Equatable {
  case folder
  case note
}

struct LibraryEntryTarget: Identifiable {
  let path: [String]
  let kind: LibraryEntryKind

  var id: String { path.joined(separator: "/") }
  var name: String { path.last ?? "Untitled" }
}

enum LibraryMutationMode {
  case createFolder
  case rename(LibraryEntryTarget)
  case move(LibraryEntryTarget)
  case restore(LibraryEntryTarget)

  var title: String {
    switch self {
    case .createFolder: "New Folder"
    case .rename: "Rename"
    case .move: "Move"
    case .restore: "Restore"
    }
  }

  var confirmation: String {
    switch self {
    case .createFolder: "Create"
    case .rename: "Rename"
    case .move: "Move"
    case .restore: "Restore"
    }
  }

  var showsName: Bool {
    switch self {
    case .createFolder, .rename: true
    case .move, .restore: false
    }
  }

  var showsFolder: Bool {
    switch self {
    case .createFolder, .move, .restore: true
    case .rename: false
    }
  }

  var initialName: String {
    switch self {
    case .createFolder: ""
    case let .rename(entry), let .move(entry), let .restore(entry): entry.name
    }
  }
}

struct LibraryMutationRequest: Identifiable {
  let id = UUID()
  let mode: LibraryMutationMode
  let folders: [FolderReference]
  let initialParent: FolderReference
}

struct LibraryMutationSheet: View {
  let request: LibraryMutationRequest
  let onApply: (String, FolderReference) -> Void
  let onCancel: () -> Void

  @State private var name: String
  @State private var parent: FolderReference

  init(
    request: LibraryMutationRequest,
    onApply: @escaping (String, FolderReference) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.request = request
    self.onApply = onApply
    self.onCancel = onCancel
    _name = State(initialValue: request.mode.initialName)
    _parent = State(initialValue: request.initialParent)
  }

  var body: some View {
    NavigationStack {
      Form {
        if request.mode.showsName {
          Section("Name") {
            TextField("Name", text: $name)
              .textInputAutocapitalization(.sentences)
          }
        }

        if request.mode.showsFolder {
          Section("Location") {
            Picker("Folder", selection: $parent) {
              ForEach(request.folders) { folder in
                Text(folder.name).tag(folder)
              }
            }
          }
        }
      }
      .navigationTitle(request.mode.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(request.mode.confirmation) {
            onApply(name, parent)
          }
          .disabled(request.mode.showsName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
